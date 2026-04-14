;;; pingwing -- The free and open Lisp-powered notification nexus

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

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

(define-restful-api v1)

(import (uuid generate)
        (json)
        (ice-9 iconv)
        (pingwing domain task)
        (pingwing sqlite task)
        (pingwing query-escape))

(post "/api/v1/tasks"
      #:mime 'json
      #:from-post 'json
      (lambda (rc)
        (catch #t
               (lambda ()
                 (let* ((raw-b (bytevector->string (rc-body rc) "utf-8"))
                        (b (json-string->scm raw-b))
                        (uid (generate-string-uuid))
                        (now (current-time))
                        (task-repo (make-sqlite-task-repository rc)))
                   
                   (insert-task task-repo
                                `((id unquote uid)
                                  (task-status . pending)
                                  (task-type unquote
                                             (assoc-ref b "task-type"))
                                  (template unquote (escape-str (assoc-ref b
                                                                   "template")))
                                  (template-vars unquote (escape-str (scm->json-string
                                                              (assoc-ref b
                                                               "template-vars"))))
                                  (sender-name unquote
                                               (escape-str (assoc-ref b
                                                            "sender-name")))
                                  (sender-address unquote
                                                  (escape-str (assoc-ref b
                                                               "sender-address")))
                                  (subject unquote
                                           (escape-str (assoc-ref b "subject")))
                                  (recipients unquote
                                              (escape-str (scm->json-string (assoc-ref
                                                                             b
                                                                             "recipients"))))
                                  (created-at unquote now)))
                   (:mime rc
                          `((message . "successfully saved task to pingwing system")))))
               (lambda (key . args)
                 (let* ((error-message (format #f
                                        "error saving task in pingwing system: ~a ~a"
                                        key args)))
                   (display error-message)
                   (http-status 500
                                (lambda ()
                                  (:mime rc
                                         `((message unquote error-message))))))))))
