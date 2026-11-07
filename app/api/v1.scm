;; pingwing - the free and open Lisp-powered notification nexus
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; The one thing a caller does: hand pingwing a task and walk away.  Because
;;; a caller walks away, a request that is wrong has to be refused clearly at
;;; once -- an unsupported task type, an unknown template, a body with no
;;; recipients -- rather than saved and discovered later as a mail that never
;;; came.  The whole endpoint is behind the basic auth the reverse proxy
;;; enforces; nothing here authenticates on its own (see the README).

(define-restful-api v1)

(import (uuid generate)
        (json)
        (ice-9 iconv)
        (ice-9 format)
        (srfi srfi-1)
        (artanis artanis)
        (pingwing domain task)
        (pingwing sqlite task))

(define known-templates
  '(password-reset system-alert lucidplan-new-ticket))

(define (non-empty-collection? x)
  "Whether X is a list or vector with at least one element."
  (cond
    ((vector? x)
     (> (vector-length x) 0))
    ((list? x)
     (pair? x))
    (else #f)))

(define (field b name)
  "The string field NAME of body B, or #f when it is missing or empty."
  (let ((v (assoc-ref b name)))
    (and v
         (string? v)
         (not (string-null? v)) v)))

;; Artanis hands the request body over as bytes; a body that arrived as a
;; string (a form post, another version) is read as it is.  Either way the
;; handler is looking at text by the time it tries to parse it.
(define (body-string rc)
  (let ((b (rc-body rc)))
    (cond
      ((string? b)
       b)
      ((bytevector? b)
       (bytevector->string b "utf-8"))
      (else (format #f "~a" b)))))

;; A JSON answer with a status of its own.  The body is turned into a string
;; here, because `:mime' cannot set a status and `response-emit' cannot measure
;; a bare alist -- handing it one answers 500 instead of the status asked for.
(define* (json-response body
                        #:key (status 200))
  (response-emit (scm->json-string body)
                 #:status status
                 #:headers '((content-type application/json))))

(define (bad-request rc message)
  (json-response `((message unquote message))
                 #:status 400))

(define (server-error rc message)
  (display message)
  (json-response `((message unquote message))
                 #:status 500))

(post "/api/v1/tasks"
      #:mime 'json
      (lambda (rc)
        (catch #t
               (lambda ()
                 (let* ((raw-b (body-string rc))
                        (b (json-string->scm raw-b))
                        (task-type (field b "task-type"))
                        (template (field b "template"))
                        (template-vars (assoc-ref b "template-vars"))
                        (recipients (assoc-ref b "recipients"))
                        (uid (generate-string-uuid))
                        (now (current-time)))
                   (cond
                     ((not (and (list? b)
                                (pair? b)))
                      (bad-request rc
                       "the request body must be a JSON object with the task's fields"))
                     ((not (equal? task-type "send-email"))
                      (bad-request rc
                                   (format #f
                                    "unsupported task-type ~s: this deployment implements only \"send-email\""
                                    task-type)))
                     ((not (memq (string->symbol (or template ""))
                                 known-templates))
                      (bad-request rc
                                   (format #f
                                    "unknown template ~s: known templates are ~a"
                                    template
                                    (string-join (map symbol->string
                                                      known-templates) ", "))))
                     ;; JSON arrays arrive as vectors from `json-string->scm',
                     ;; so both readings of a list are accepted here.
                     ((not (non-empty-collection? recipients))
                      (bad-request rc
                       "recipients must be a non-empty list of {name, address} objects"))
                     ((not (list? template-vars))
                      (bad-request rc
                       "template-vars must be a JSON object of the template's variables"))
                     ((not (field b "sender-address"))
                      (bad-request rc "sender-address is required"))
                     ((not (field b "subject"))
                      (bad-request rc "subject is required"))
                     (else
                      ;; The values go in as they arrived.  Nothing is escaped
                      ;; into the statement here: the sqlite layer binds every
                      ;; value, so a subject is a subject and not a piece of
                      ;; SQL, and a task read back is the task that was sent.
                      (let ((task-repo (make-sqlite-task-repository)))
                        (insert-task task-repo
                                     `((id unquote uid)
                                       (task-status . "pending")
                                       (task-type unquote task-type)
                                       (template unquote template)
                                       (template-vars unquote
                                                      (scm->json-string
                                                       template-vars))
                                       (sender-name unquote
                                                    (or (field b "sender-name")
                                                        ""))
                                       (sender-address unquote
                                                       (field b
                                                        "sender-address"))
                                       (subject unquote
                                                (field b "subject"))
                                       (recipients unquote
                                                   (scm->json-string
                                                    recipients))
                                       (created-at unquote now)
                                       (attempts . 0)
                                       (last-error . "")))
                        (json-response `((message . "successfully saved task to pingwing system")
                                         (id unquote uid))
                                       #:status 201))))))
               (lambda (key . args)
                 (server-error rc
                               (format #f
                                "error saving task in pingwing system: ~a ~a"
                                key args))))))

;; A shallow liveness probe for a reverse proxy or an uptime check.  It needs
;; no mail credentials and does not touch the database, so it answers exactly
;; the question it is asked: is the application up and routing?
(get "/api/v1/health"
     #:mime 'json
     (lambda (rc)
       (json-response `((status . "ok") (service . "pingwing")))))

;; The queue, made legible: the latest tasks with only the fields an operator
;; needs.  The template variables and the recipients are deliberately left out
;; -- a password-reset link is a secret, and listing it would put one on the
;; wire for no reason.  Behind the same basic auth as everything else.
(get "/api/v1/tasks"
     #:mime 'json
     (lambda (rc)
       (define (public-task t)
         `((id unquote
               (assq-ref t
                         'id))
           (task-status unquote
                        (assq-ref t
                                  'task-status))
           (task-type unquote
                      (assq-ref t
                                'task-type))
           (template unquote
                     (assq-ref t
                               'template))
           (sender-address unquote
                           (assq-ref t
                                     'sender-address))
           (subject unquote
                    (assq-ref t
                              'subject))
           (attempts unquote
                     (assq-ref t
                               'attempts))
           (last-error unquote
                       (assq-ref t
                                 'last-error))
           (created-at unquote
                       (assq-ref t
                                 'created-at))
           (updated-at unquote
                       (assq-ref t
                                 'updated-at))))
       (catch #t
              (lambda ()
                (let* ((repo (make-sqlite-task-repository))
                       (limit (string->number (or (get-from-qstr rc "limit")
                                                  "50")))
                       (tasks (get-recent-tasks repo
                                                (or limit 50))))
                  (json-response (list->vector (map public-task tasks)))))
              (lambda (key . args)
                (server-error rc
                              (format #f
                               "error listing tasks from pingwing system: ~a ~a"
                               key args))))))
