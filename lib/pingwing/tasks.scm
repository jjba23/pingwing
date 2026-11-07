;; pingwing - the free and open Lisp-powered notification nexus
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; The queue and what runs it.
;;;
;;; Ingestion and delivery are two processes that only meet in a row of the
;;; `tasks' table, and this is the second one.  A sweep of the worker takes a
;;; batch of pending tasks, claims each, and runs as many of them at a time as
;;; it was told to -- a task per fiber, on a `run-fibers' scheduler that the
;;; sweep makes and drains, exactly the shape byggsteg's own queue uses.
;;;
;;; A send is libcurl's to make, and libcurl's easy interface blocks the thread
;;; it is called on; a fiber that called it directly would freeze the whole
;;; sweep behind one message.  So the blocking call is handed to a thread of
;;; its own, and the fiber waits on a condition the thread signals -- fibers
;;; for the orchestration and the back-pressure, a bounded handful of threads
;;; for the work that genuinely blocks.  The batch and its concurrency are both
;;; settings, so a deployment tunes the pressure it puts on its mail server.
;;;
;;; A task is retried on two clocks.  Inside one delivery there are the SMTP
;;; tries and their growing backoff (see `(pingwing mail)'), for a connection
;;; that blinks.  Across sweeps a task that still failed is left pending until
;;; it has burned through `max-task-attempts', so a mail server that is down
;;; for a minute is waited out rather than losing the message -- and when it
;;; finally gives up, or when a template it names does not exist, the task goes
;;; to `failed' with `last_error' saying why.

(define-module (pingwing tasks)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 iconv)
  #:use-module ((ice-9 match)
                #:select (match ))
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 string-fun)
  #:use-module (json)
  #:use-module (kracht prelude)
  #:use-module (pingwing mail)
  #:use-module (pingwing base64)
  #:use-module (pingwing templates password-reset)
  #:use-module (pingwing templates system-alert)
  #:use-module (pingwing templates lucidplan-new-ticket)
  #:use-module (ice-9 pretty-print)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:use-module (artanis artanis)
  #:use-module (web request)
  #:use-module (web uri)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:use-module (pingwing sqlite task)
  #:use-module (pingwing domain task)
  ;; `(fibers)' and `(ice-9 threads)' both name `sleep'.  The worker paces
  ;; itself between sweeps -- on the ordinary thread that runs it -- so the
  ;; fiber one is hidden and every `sleep' below is the blocking thread's.
  #:use-module ((fibers)
                #:hide (sleep))
  #:use-module (fibers conditions)
  #:use-module (ice-9 atomic)
  #:use-module (ice-9 threads)
  ;; `#:re-export', not `#:export': a name listed in `#:export' is taken to be
  ;; one the module defines, which would shadow the import of the same name
  ;; and leave it unbound.  `pingwing-send-mail' is the sender's, offered here
  ;; because this is where it used to live.
  #:re-export (pingwing-send-mail)
  #:export (pingwing-worker-thread pingwing-task-processor
                                   do-send-mail
                                   body-from-task
                                   html-body-from-task
                                   run-sweep
                                   run-one-task
                                   run-tasks-concurrently
                                   call-blocking))

;;; --------------------------------------------------------------- logging

;; The queue's own logger, configured the way byggsteg's is: from the
;; environment, with a human-readable console layout unless a deployment asks
;; for JSON.  Every line the worker writes goes through it.
(define log
  (scriba-auto-logger))

;;; ------------------------------------------------------------- settings

;; Settings arrive as an alist of groups (`mail', `pingwing') whose own values
;; are alists.  A setting a deployment did not write falls back to the default
;; here, so an env.scm written before a knob existed still starts.
(define (setting settings group key default)
  (let* ((g (and (list? settings)
                 (assoc-ref settings group)))
         (v (and g
                 (assoc-ref g key))))
    (if v v default)))

;;; --------------------------------------------------- blocking, off-fiber

(define (call-blocking thunk)
  "Run THUNK on a thread of its own and answer what it answers.

The calling fiber is suspended until the thread is done -- rather than the
whole worker being blocked -- which is what lets a sweep keep several sends in
the air at once even though libcurl blocks the thread it runs on."
  (let ((done (make-condition))
        (box (make-atomic-box #f)))
    (call-with-new-thread (lambda ()
                            (atomic-box-set! box
                                             (catch #t thunk
                                                    (lambda (key . args)
                                                      (cons #f
                                                            (format #f "~a ~a"
                                                                    key
                                                                    (if (null?
                                                                         args)
                                                                        ""
                                                                        (format
                                                                         #f
                                                                         "~s"
                                                                         args)))))))
                            (signal-condition! done)))
    (wait done)
    (atomic-box-ref box)))

;;; ------------------------------------------------------------- templates

;; The message a task asks for.  An unknown template is not silently sent as
;; an empty message: the processor refuses it and records why, which is far
;; easier to act on than a mail that arrives blank.
(define (task-template task)
  (string->symbol (assq-ref task
                            'template)))

(define (task-vars task)
  (json-string->scm (assq-ref task
                              'template-vars)))

(define (template-var v key)
  (assoc-ref v key))

(define* (body-from-task #:key task)
  (let ((v (task-vars task)))
    (match (task-template task)
      ('password-reset (password-reset-plain-template #:system-name (template-var
                                                                     v
                                                                     "system-name")
                                                      #:user (template-var v
                                                              "user")
                                                      #:reset-link (template-var
                                                                    v
                                                                    "reset-link")))
      ('system-alert (system-alert-plain-template #:system-name (template-var
                                                                 v
                                                                 "system-name")
                                                  #:alert-value (template-var
                                                                 v
                                                                 "alert-value")))
      ('lucidplan-new-ticket (lucidplan-new-ticket-plain-template
                                                                  #:system-name
                                                                  (template-var
                                                                   v
                                                                   "system-name")
                                                                  #:project-name
                                                                  (template-var
                                                                   v
                                                                   "project-name")
                                                                  #:project-human-id
                                                                  (template-var
                                                                   v
                                                                   "project-human-id")
                                                                  #:ticket-human-id
                                                                  (template-var
                                                                   v
                                                                   "ticket-human-id")
                                                                  #:ticket-title
                                                                  (template-var
                                                                   v
                                                                   "ticket-title")
                                                                  #:ticket-type
                                                                  (template-var
                                                                   v
                                                                   "ticket-type")
                                                                  #:ticket-status
                                                                  (template-var
                                                                   v
                                                                   "ticket-status")
                                                                  #:priority (template-var
                                                                              v
                                                                              "priority")
                                                                  #:author (template-var
                                                                            v
                                                                            "author")
                                                                  #:assignee (template-var
                                                                              v
                                                                              "assignee")
                                                                  #:description
                                                                  (template-var
                                                                   v
                                                                   "description")
                                                                  #:ticket-url
                                                                  (template-var
                                                                   v
                                                                   "ticket-url")))
      (_ #f))))

(define* (html-body-from-task #:key task)
  (let ((v (task-vars task)))
    (match (task-template task)
      ('password-reset (password-reset-html-template #:system-name (template-var
                                                                    v
                                                                    "system-name")
                                                     #:user (template-var v
                                                             "user")
                                                     #:reset-link (template-var
                                                                   v
                                                                   "reset-link")))
      ('system-alert (system-alert-html-template #:system-name (template-var v
                                                                "system-name")
                                                 #:alert-value (template-var v
                                                                "alert-value")))
      ('lucidplan-new-ticket (lucidplan-new-ticket-html-template #:system-name
                                                                 (template-var
                                                                  v
                                                                  "system-name")
                                                                 #:project-name
                                                                 (template-var
                                                                  v
                                                                  "project-name")
                                                                 #:project-human-id
                                                                 (template-var
                                                                  v
                                                                  "project-human-id")
                                                                 #:ticket-human-id
                                                                 (template-var
                                                                  v
                                                                  "ticket-human-id")
                                                                 #:ticket-title
                                                                 (template-var
                                                                  v
                                                                  "ticket-title")
                                                                 #:ticket-type
                                                                 (template-var
                                                                  v
                                                                  "ticket-type")
                                                                 #:ticket-status
                                                                 (template-var
                                                                  v
                                                                  "ticket-status")
                                                                 #:priority (template-var
                                                                             v
                                                                             "priority")
                                                                 #:author (template-var
                                                                           v
                                                                           "author")
                                                                 #:assignee (template-var
                                                                             v
                                                                             "assignee")
                                                                 #:description
                                                                 (template-var
                                                                  v
                                                                  "description")
                                                                 #:ticket-url (template-var
                                                                               v
                                                                               "ticket-url")))
      (_ #f))))

(define (known-templates)
  '(password-reset system-alert lucidplan-new-ticket))

;;; --------------------------------------------------------------- sending

(define* (do-send-mail #:key task recipient settings)
  "Deliver TASK's message to one RECIPIENT, answering `(cons ok? detail)'."
  (let ((v (assoc-ref settings
                      'mail)))
    (call-blocking (lambda ()
                     (pingwing-send-mail #:id (assq-ref task
                                                        'id)
                                         #:access-key (assoc-ref v
                                                                 'access-key)
                                         #:access-secret (assoc-ref v
                                                                    'access-secret)
                                         #:access-server (assoc-ref v
                                                                    'access-server)
                                         #:access-port (assoc-ref v
                                                                  'access-port)
                                         #:from-name (assq-ref task
                                                               'sender-name)
                                         #:from-address (assq-ref task
                                                                  'sender-address)
                                         #:to-name (assoc-ref recipient "name")
                                         #:to-address (assoc-ref recipient
                                                                 "address")
                                         #:subject (assq-ref task
                                                             'subject)
                                         #:body (body-from-task #:task task)
                                         #:body-html (html-body-from-task
                                                      #:task task)
                                         #:attempts (setting settings
                                                             'mail
                                                             'attempts 3)
                                         #:retry-base-seconds (setting
                                                               settings
                                                               'mail
                                                               'retry-delay-seconds
                                                               3)
                                         #:tmp-dir (setting settings
                                                            'mail
                                                            'tmp-dir "tmp")
                                         #:use-ssl (setting settings
                                                            'mail
                                                            'use-ssl 1)
                                         #:verbose (setting settings
                                                            'mail
                                                            'verbose #f))))))

(define (failures->text failures)
  (string-join (map cdr failures) " | "))

(define* (pingwing-task-processor #:key task-repo task settings)
  "Handle one task: build its message, deliver it to each recipient, and write
down what happened.  A task that is still failing but has retries left goes
back to `pending'; one that has used them up goes to `failed' with the reasons."
  (log-info log
            (gettext "processing pingwing task"))
  (let* ((id (assq-ref task
                       'id))
         (template (task-template task))
         (this-attempt (+ 1
                          (or (assq-ref task
                                        'attempts) 0)))
         (max-attempts (setting settings
                                'pingwing
                                'max-task-attempts 5))
         (now (current-time))
         (body (and (memq template
                          (known-templates))
                    (body-from-task #:task task))))
    (if (not body)
        (begin
          (display (format #f "
task ~a names no template pingwing knows: ~a
" id
                           template))
          (update-task-by-id task-repo id
                             `((task-status . failed) (attempts unquote
                                                                this-attempt)
                               (last-error unquote
                                           (format #f
                                            "unknown template: ~a (known: ~a)"
                                            template
                                            (string-join (map symbol->string
                                                              (known-templates))
                                                         ", ")))
                               (updated-at unquote now))))
        (let* ((recipients (vector->list (json-string->scm (assq-ref task
                                                                     'recipients))))
               (results (map (lambda (recipient)
                               (do-send-mail #:task task
                                             #:recipient recipient
                                             #:settings settings)) recipients))
               (failures (filter (lambda (r)
                                   (not (car r))) results)))
          (cond
            ((null? failures)
             (log-info log
                       (gettext "pingwing task complete"))
             (update-task-by-id task-repo id
                                `((task-status . complete) (attempts unquote
                                                            this-attempt)
                                  (last-error . "")
                                  (updated-at unquote now))))
            ((< this-attempt max-attempts)
             (display (format #f
                       "
task ~a did not go out (attempt ~a of ~a), requeued:
  ~a
"
                       id
                       this-attempt
                       max-attempts
                       (failures->text failures)))
             (update-task-by-id task-repo id
                                `((task-status . pending) (attempts unquote
                                                           this-attempt)
                                  (last-error unquote
                                              (failures->text failures))
                                  (updated-at unquote now))))
            (else (display (format #f "
task ~a gave up after ~a attempts:
  ~a
" id
                                   this-attempt
                                   (failures->text failures)))
                  (update-task-by-id task-repo id
                                     `((task-status . failed) (attempts
                                                               unquote
                                                               this-attempt)
                                       (last-error unquote
                                                   (failures->text failures))
                                       (updated-at unquote now)))))))))

;;; -------------------------------------------------------------- the queue

(define* (run-tasks-concurrently tasks concurrency run-one)
  "Run RUN-ONE over TASKS with at most CONCURRENCY of them in flight.

Each worker takes the next task from the shared queue as it frees up rather
than being handed a fixed share, and the call returns once every task has been
run.  The queue is a plain list that the workers read the head of and move on;
fibers only switch at operations, so no two workers can take the same task."
  (if (null? tasks) #t
      (let* ((workers (min (max 1 concurrency)
                           (length tasks)))
             (finished (make-condition))
             (stopped (make-atomic-box 0))
             (queue tasks))
        (define (next-task)
          (let ((task (car queue)))
            (set! queue
                  (cdr queue)) task))
        (define (work-through-queue)
          (if (null? queue) #t
              (begin
                (run-one (next-task))
                (work-through-queue))))
        (for-each (lambda (n)
                    (spawn-fiber (lambda ()
                                   ;; A worker counts itself stopped even if it raises, or
                                   ;; the sweep below would wait for it for ever.
                                   (catch #t work-through-queue
                                          (lambda (key . args)
                                            (display (format #f
                                                      "\n  a queue worker stopped: ~a ~s\n"
                                                      key args))))
                                   (let ((count (+ 1
                                                   (atomic-box-ref stopped))))
                                     (atomic-box-set! stopped count)
                                     (when (>= count workers)
                                       (signal-condition! finished))))))
                  (iota workers))
        (wait finished) #t)))

(define* (run-one-task #:key task-repo task settings)
  "Run TASK and make sure its row says how it went, whatever happens."
  (catch #t
         (lambda ()
           (pingwing-task-processor #:task-repo task-repo
                                    #:task task
                                    #:settings settings))
         (lambda (key . args)
           (let ((reason (format #f "~a ~a" key
                                 (if (null? args) ""
                                     (format #f "~s" args)))))
             (display (format #f "\n  could not process task ~a: ~a\n"
                              (assq-ref task
                                        'id) reason))
             (update-task-by-id task-repo
                                (assq-ref task
                                          'id)
                                `((task-status . failed) (last-error unquote
                                                                     reason)
                                  (updated-at unquote
                                              (current-time))))))))

(define* (run-sweep #:key task-repo settings)
  "One visit to the queue: requeue what a stopped worker left, then run a
batch of pending tasks concurrently.  Answers the number of tasks it ran."
  (requeue-stale-processing-tasks task-repo
                                  (setting settings
                                           'pingwing
                                           'stale-processing-seconds 600))
  (let* ((limit (setting settings
                         'pingwing
                         'worker-batch-limit 16))
         (concurrency (setting settings
                               'pingwing
                               'worker-concurrency 4))
         (tasks (get-pending-tasks task-repo limit)))
    (if (null? tasks) 0
        (begin
          ;; Claim before running, so a task a crash interrupted is not run
          ;; twice: only a pending row is taken, and claiming moves it on.
          (for-each (lambda (task)
                      (catch #t
                             (lambda ()
                               (claim-task-by-id task-repo
                                                 (assq-ref task
                                                           'id)))
                             (lambda (key . args)
                               (display (format #f
                                         "\n  could not claim task ~a: ~a ~s\n"
                                         (assq-ref task
                                                   'id) key args))))) tasks)
          (log-info log
                    (gettext "running a batch of pingwing tasks: ~a")
                    (length tasks))
          (run-fibers (lambda ()
                        (run-tasks-concurrently tasks concurrency
                                                (lambda (task)
                                                  (run-one-task #:task-repo
                                                                task-repo
                                                                #:task task
                                                                #:settings
                                                                settings))))
                      #:drain? #t)
          (length tasks)))))

(define* (pingwing-worker-thread #:key task-repo settings)
  "The queue worker: sweep, rest, sweep again, for as long as the process lives."
  (log-info log
            (gettext "initializing pingwing queue worker"))
  (catch #t
         (lambda ()
           (mkdir (setting settings
                           'mail
                           'tmp-dir "tmp")))
         (lambda (key . args)
           '()))
  (let ((pause (setting settings
                        'pingwing
                        'worker-sleep-seconds 5)))
    (while #t
           (catch #t
                  (lambda ()
                    (run-sweep #:task-repo task-repo
                               #:settings settings))
                  (lambda (key . args)
                    (display (format #f
                                     "\n  the pingwing sweep stopped: ~a ~s\n"
                                     key args))))
           (sleep pause))))
