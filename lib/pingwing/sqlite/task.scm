;; pingwing - the free and open Lisp-powered notification nexus
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; The tasks table, read and written through `(kracht sql)'.
;;
;; Every statement below is a kracht builder: the SQL text and the values travel
;; separately, and `(pingwing sqlite util)' binds the values into the statement
;; after it has been prepared.  Nothing here quotes, escapes or formats a value
;; into a string, so a subject or an error message that came from outside cannot
;; be read as SQL -- it can only be read as a value.

(define-module (pingwing sqlite task)
  #:declarative? #t
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 time)
  #:use-module (kracht prelude)
  #:use-module (kracht sql)
  #:use-module (pingwing sqlite util)
  #:use-module (pingwing domain task)
  #:export (make-sqlite-task-repository))

;; NOTE: a row list is read with `null?' rather than a prelude shorthand, so
;; that what an empty answer looks like is spelled out where it is tested.

;; --- SQLite implementation ---
(define (make-sqlite-task-repository)
  ;; The metadata columns, in the order an operator reads them.  The template
  ;; variables and the recipients are in this list because a task row is what
  ;; the queue works from; `get-recent-tasks' names a narrower list, since a
  ;; reset link is a secret and has no business on the way to a browser.
  (define columns
    '(id task-status
         task-type
         template
         template-vars
         sender-name
         sender-address
         subject
         recipients
         created-at
         updated-at
         attempts
         last-error))

  (define execute-read
    (db-read (database)))

  (define execute-write
    (db-write (database)))

  ;; A limit a caller asked for is clamped here rather than trusted: a
  ;; mis-set setting must not be able to ask the database for a negative
  ;; number of rows, and one that is absurdly large is a sweep nobody wants.
  (define (row-limit limit default)
    (if (and limit
             (number? limit)
             (> limit 0))
        (inexact->exact limit) default))

  (define (get-next-pending-task)
    ;; One row, oldest first: the order is what keeps the queue fair, since the
    ;; oldest message is always the next one taken.
    (let ((rows (execute-read "get-next-pending-task"
                              (sql-select "tasks"
                                          #:columns columns
                                          #:where '((task-status . "pending"))
                                          #:order-by '((created-at asc))
                                          #:limit 1))))
      (if (null? rows) #f
          (car rows))))

  ;; A sweep's worth of work, oldest first.
  (define (get-pending-tasks limit)
    (execute-read "get-pending-tasks"
                  (sql-select "tasks"
                              #:columns columns
                              #:where '((task-status . "pending"))
                              #:order-by '((created-at asc))
                              #:limit (row-limit limit 16))))

  ;; The metadata columns only: the list an operator reads must not carry a
  ;; password-reset link or a recipient list onto the wire.
  (define (get-recent-tasks limit)
    (execute-read "get-recent-tasks"
                  (sql-select "tasks"
                              #:columns '(id task-status
                                             task-type
                                             template
                                             sender-address
                                             subject
                                             attempts
                                             last-error
                                             created-at
                                             updated-at)
                              #:order-by '((created-at desc))
                              #:limit (row-limit limit 50))))

  (define (claim-task-by-id id)
    ;; Only a task that is still pending is claimed, so a task another sweep
    ;; already took is left alone.  The two conditions are one statement, which
    ;; is what makes the claim atomic rather than a read followed by a write.
    (execute-write "claim-task-by-id"
                   (sql-update "tasks"
                               `((task-status . "processing") (updated-at
                                                               unquote
                                                               (current-time)))
                               #:where (list (cons 'id id)
                                             (cons 'task-status "pending")))))

  (define (requeue-stale-processing-tasks stale-seconds)
    ;; A worker that stopped mid-delivery leaves its task marked processing with
    ;; nothing running it.  The reading is "processing and either never updated
    ;; or last touched before the threshold", and an OR is outside what the
    ;; condition lists above express -- which is what `sql-parameterize' is for.
    (let ((threshold (- (current-time)
                        (max 1
                             (inexact->exact (if (and stale-seconds
                                                      (number? stale-seconds))
                                                 stale-seconds 600))))))
      (execute-write "requeue-stale-processing-tasks"
                     (sql-parameterize
                      "UPDATE \"tasks\" SET \"task_status\" = ? WHERE \"task_status\" = ? AND (\"updated_at\" IS NULL OR \"updated_at\" < ?)"
                      (list "pending" "processing" threshold)))))

  (define (delete-task-by-id id)
    (execute-write "delete-task-by-id"
                   (sql-delete "tasks"
                               #:where (list (cons 'id id)))))

  (define (update-task-by-id id attrs)
    (execute-write "update-task-by-id"
                   (sql-update "tasks" attrs
                               #:where (list (cons 'id id)))))

  ;; The column list comes from the attributes themselves, so a column the
  ;; caller did not name keeps the default its row was created with -- and a
  ;; caller cannot insert into a column by naming it in a value.
  (define (insert-task attrs)
    (execute-write "insert-task"
                   (sql-insert "tasks" attrs)))

  (mk-task-repository #:get-next-pending-task-proc get-next-pending-task
                      #:get-pending-tasks-proc get-pending-tasks
                      #:get-recent-tasks-proc get-recent-tasks
                      #:claim-task-by-id-proc claim-task-by-id
                      #:requeue-stale-processing-tasks-proc
                      requeue-stale-processing-tasks
                      #:update-task-by-id-proc update-task-by-id
                      #:insert-task-proc insert-task
                      #:delete-task-by-id-proc delete-task-by-id))
