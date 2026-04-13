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

(define-module (pingwing domain task)
  #:declarative? #t
  #:use-module (pingwing domain repo)
  #:use-module (srfi srfi-9)
  #:export (get-next-pending-task insert-task delete-task-by-id))

;; -- Record definition ---

(define-record-with-kw (<task-repository> %make-task-repository
                                          task-repository?)
                       mk-task-repository
                       (get-next-pending-task-proc repo-get-tasks-in-progress)
                       (insert-task-proc repo-insert-task)
                       (update-task-proc repo-update-task)
                       (delete-task-by-id-proc repo-delete-task-by-id))

;; --- eDSL: Embedded Domain Specific Language ---

(define-repo-method get-next-pending-task repo-get-next-pending-task
                    "Retrieves a the next queued task from the given REPO.")

(define-repo-method insert-task repo-insert-task
                    "Inserts a task with ATTRS in the given REPO.")

(define-repo-method update-task repo-update-task
                    "Updates a task with ATTRS in the given REPO.")

(define-repo-method delete-task-by-id repo-delete-task-by-id
                    "Deletes a task identified by ID in the given REPO.")
