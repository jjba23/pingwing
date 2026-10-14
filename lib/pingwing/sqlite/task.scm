;;; pingwing -- The free and open Lisp-powered notification nexus

;; Copyright © Josep Bigorra known as "jjba23" <jjbigorra@gmail.com>

;; pingwing is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; pingwing is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public License
;; along with pingwing.  If not, see <https://www.gnu.org/licenses/>.

(define-module (pingwing sqlite task)
  #:declarative? #t
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 time)
  #:use-module (kracht prelude)
  #:use-module (artanis db)
  #:use-module (pingwing sqlite util)
  #:use-module (pingwing domain task)
  #:export (make-sqlite-task-repository))

;; --- SQLite implementation ---
(define (make-sqlite-task-repository rc)
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

  (define insert-columns
    '(id task-status
         task-type
         template
         template-vars
         sender-name
         sender-address
         subject
         recipients
         created-at
         attempts
         last-error))

  (define conn
    (DB-open rc))

  (define (query-all columns-sql where-sql)
    (let* ((query (format #f
                   "SELECT ~a FROM tasks WHERE ~a"
                   columns-sql where-sql))
           (rows (map sql-row->scheme-alist
                      (DB-get-all-rows (DB-query conn query)))))
      (if (nil? rows) '()
          rows)))

  (define (get-next-pending-task)
    (let ((rows (query-all (symbols->sql-columns-list columns)
                           "task_status = 'pending'
                            ORDER BY created_at ASC LIMIT 1")))
      (if (nil? rows) #f
          (car rows))))

  ;; A sweep's worth of work, oldest first.  LIMIT is clamped so that a
  ;; mis-set setting cannot ask the database for a negative number of rows.
  (define (get-pending-tasks limit)
    (let ((limit (cond ((and limit (number? limit) (> limit 0))
                        (inexact->exact limit))
                       (else 16))))
      (query-all (symbols->sql-columns-list columns)
                 (format #f "task_status = 'pending'
                             ORDER BY created_at ASC LIMIT ~a" limit))))

  ;; The metadata columns only: the list an operator reads must not carry a
  ;; password-reset link or a recipient list onto the wire.
  (define (get-recent-tasks limit)
    (let ((limit (cond ((and limit (number? limit) (> limit 0))
                        (inexact->exact limit))
                       (else 50))))
      (query-all
       (symbols->sql-columns-list
        '(id task-status task-type template sender-address subject attempts
             last-error created-at updated-at))
       (format #f "1 = 1 ORDER BY created_at DESC LIMIT ~a" limit))))

  (define (claim-task-by-id id)
    (let* ((query (format #f
                   "UPDATE tasks SET task_status = 'processing', updated_at = ~a
                    WHERE id = ~a AND task_status = 'pending'"
                   (current-time) (value->sql-literal id)))
           (_ (log-info "claim-task-by-id query:\n\t~a\n" query)))
      (DB-query conn query)))

  (define (requeue-stale-processing-tasks stale-seconds)
    (let* ((threshold (- (current-time)
                         (max 1 (inexact->exact (if (and stale-seconds
                                                         (number? stale-seconds))
                                                    stale-seconds
                                                    600)))))
           (query (format #f
                   "UPDATE tasks SET task_status = 'pending'
                    WHERE task_status = 'processing'
                      AND (updated_at IS NULL OR updated_at < ~a)"
                   threshold))
           (_ (log-info "requeue-stale-processing-tasks: ~a" query)))
      (DB-query conn query)))

  (define (delete-task-by-id id)
    (let* ((query (format #f "DELETE FROM tasks WHERE id = ~a"
                          (value->sql-literal id)))
           (_ (log-info "delete-task-by-id query:\n\t~a\n" query))
           (r (DB-query conn query)))
      r))

  (define (update-task-by-id id attrs)
    (let* ((query (format #f "UPDATE tasks SET ~a WHERE id = ~a"
                          (string-join (map pair->sql-assignment attrs) ", ")
                          (value->sql-literal id)))
           (_ (log-info "update-task-by-id query:\n\t~a\n" query))
           (r (DB-query conn query)))
      r))

  (define (insert-task attrs)
    (let* ((vals (map (lambda (x)
                        (value->sql-literal (assq-ref attrs x)))
                      insert-columns))
           (query (format #f "INSERT INTO tasks (~a) VALUES (~a)"
                          (symbols->sql-columns-list insert-columns)
                          (string-join vals ", ")))
           (_ (log-info "insert-task query:\n\t~a\n" query))
           (r (DB-query conn query)))
      r))

  (mk-task-repository #:get-next-pending-task-proc get-next-pending-task
                      #:get-pending-tasks-proc get-pending-tasks
                      #:get-recent-tasks-proc get-recent-tasks
                      #:claim-task-by-id-proc claim-task-by-id
                      #:requeue-stale-processing-tasks-proc
                      requeue-stale-processing-tasks
                      #:update-task-by-id-proc update-task-by-id
                      #:insert-task-proc insert-task
                      #:delete-task-by-id-proc delete-task-by-id))
