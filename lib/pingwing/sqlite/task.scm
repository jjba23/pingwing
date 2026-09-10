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
         attempts))

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
         attempts))

  (define conn
    (DB-open rc))

  (define (get-next-pending-task)
    (let* ((query (format #f
                   "SELECT ~a FROM tasks WHERE task_status = 'pending'
                    ORDER BY created_at ASC LIMIT 1"
                   (symbols->sql-columns-list columns)))
           (_ (log-debug "get-next-pending-task query:\n\t~a\n" query))
           (rows (map sql-row->scheme-alist
                      (DB-get-all-rows (DB-query conn query))))
           (_ (log-debug "get-next-pending-task rows: ~a\n"
                        (length rows))))
      (if (nil? rows) #f
          (car rows))))

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
                      #:update-task-by-id-proc update-task-by-id
                      #:insert-task-proc insert-task
                      #:delete-task-by-id-proc delete-task-by-id))
