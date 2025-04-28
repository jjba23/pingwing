;;; pingwing

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; pingwing is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; pingwing is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with pingwing.  If not, see <https://www.gnu.org/licenses/>.

(define-module (pingwing tasks)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 regex)
  #:use-module (app models task)
  #:use-module (srfi srfi-1)
  #:use-module (artanis db)
  #:use-module (artanis ssql)
  #:use-module (srfi srfi-64)
  #:use-module (pingwing process)
  #:use-module (pingwing query-escape)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 iconv))

(define-public (pingwing-worker-thread)
  (display (format #f "\n~a...\n"
                   (gettext "initializing pingwing queue worker")))

  (use-modules (pingwing tasks)
               (app models task))

  (while #t
    (let* ((oldest-task-not-done ($task 'get
                                        #:ret 1
                                        #:condition (where #:task_status
                                                           "pending")
                                        #:order-by "created_at ASC")))
      (unless (nil? oldest-task-not-done)
        (display "\n================\nprocessing pingwing task\n")
        (display oldest-task-not-done))
      (sleep 3))))
