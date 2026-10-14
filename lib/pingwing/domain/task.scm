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
  #:export (get-next-pending-task get-pending-tasks
                                  get-recent-tasks
                                  insert-task
                                  claim-task-by-id
                                  requeue-stale-processing-tasks
                                  delete-task-by-id
                                  update-task-by-id))

;; -- Record definition ---

(define-record-with-kw (<task-repository> %make-task-repository
                                          task-repository?)
                       mk-task-repository
                       (get-next-pending-task-proc repo-get-next-pending-task)
                       (get-pending-tasks-proc repo-get-pending-tasks)
                       (get-recent-tasks-proc repo-get-recent-tasks)
                       (claim-task-by-id-proc repo-claim-task-by-id)
                       (requeue-stale-processing-tasks-proc
                        repo-requeue-stale-processing-tasks)
                       (insert-task-proc repo-insert-task)
                       (update-task-by-id-proc repo-update-task-by-id)
                       (delete-task-by-id-proc repo-delete-task-by-id))

;; --- eDSL: Embedded Domain Specific Language ---

(define-repo-method get-next-pending-task repo-get-next-pending-task
                    "Retrieves the oldest pending task from the given REPO.")

(define-repo-method get-pending-tasks repo-get-pending-tasks
 "Retrieves up to LIMIT pending tasks, oldest first, from REPO.

A worker takes a batch rather than one task at a time so that it can run a
sweep of them concurrently; the order is what keeps the queue fair, since the
oldest message is always in the next batch.")

(define-repo-method get-recent-tasks repo-get-recent-tasks
 "Retrieves up to LIMIT tasks, newest first, from REPO.

Only the metadata an operator reads is asked for -- never the template
variables, which may hold a reset link, nor the recipients.")

(define-repo-method claim-task-by-id repo-claim-task-by-id
 "Marks the pending task ID as being processed in REPO.

Only a task that is still pending is claimed, so a task that another sweep
already took is left alone.  A claim is what lets an interrupted worker's work
be told apart from work that is genuinely still on the way.")

(define-repo-method requeue-stale-processing-tasks
 repo-requeue-stale-processing-tasks
 "Returns tasks stuck processing for STALE-SECONDS to pending.

A worker that stops mid-delivery -- a restart, a crash, a pulled plug -- leaves
its task marked processing with nothing running it.  On the next sweep those
older than STALE-SECONDS are put back in the queue, which is what makes a
restart lose no message.")

(define-repo-method insert-task repo-insert-task
                    "Inserts a task with ATTRS in the given REPO.")

(define-repo-method update-task-by-id repo-update-task-by-id
                    "Updates a task by ID with ATTRS in the given REPO.")

(define-repo-method delete-task-by-id repo-delete-task-by-id
                    "Deletes a task identified by ID in the given REPO.")
