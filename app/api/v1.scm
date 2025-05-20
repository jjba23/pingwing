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
        (ice-9 iconv))
(import (app models task)
        (pingwing query-escape))

(get "/api/v1/tasks"
     #:mime 'json
     (lambda (rc)
       (let* ((tasks ($task 'get
                            #:order-by "created_at DESC"))
              (formatted-tasks (map (lambda (t)
                                      `((id unquote
                                            (assoc-ref t "id"))
                                        (task-status unquote
                                                     (unescape-str (assoc-ref
                                                                    t
                                                                    "task_status")))
                                        (task-type unquote
                                                   (unescape-str (assoc-ref t
                                                                  "task_type")))
                                        (template unquote
                                                  (unescape-str (assoc-ref t
                                                                 "template")))
                                        (template-vars unquote
                                                       (json-string->scm (unescape-str
                                                                          (assoc-ref
                                                                           t
                                                                           "template_vars"))))
                                        (sender-name unquote
                                                     (unescape-str (assoc-ref
                                                                    t
                                                                    "sender_name")))
                                        (sender-address unquote
                                                        (unescape-str (assoc-ref
                                                                       t
                                                                       "sender_address")))
                                        (subject unquote
                                                 (unescape-str (assoc-ref t
                                                                "subject")))
                                        (recipients unquote
                                                    (json-string->scm (unescape-str
                                                                       (assoc-ref
                                                                        t
                                                                        "recipients"))))
                                        (created-at unquote
                                                    (assoc-ref t "created_at"))
                                        (updated-at unquote
                                                    (assoc-ref t "updated_at"))))
                                    tasks)))
         (:mime rc
                (list->vector formatted-tasks)))))

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
                        (message (format #f
                                  "successfully saved task to pingwing system")))
                   ($task 'set
                          #:id uid
                          #:task_status 'pending
                          #:task_type (assoc-ref b "task-type")
                          #:template (escape-str (assoc-ref b "template"))
                          #:template_vars (escape-str (scm->json-string (assoc-ref
                                                                         b
                                                                         "template-vars")))
                          #:sender_name (escape-str (assoc-ref b "sender-name"))
                          #:sender_address (escape-str (assoc-ref b
                                                        "sender-address"))
                          #:subject (escape-str (assoc-ref b "subject"))
                          #:recipients (escape-str (scm->json-string (assoc-ref
                                                                      b
                                                                      "recipients")))
                          #:created_at now)
                   (:mime rc
                          `((message unquote message)))))
               (lambda (key . args)
                 (let* ((message (format #f
                                  "error saving task in pingwing system: ~a ~a"
                                  key args)))
                   (display message)
                   (http-status 500
                                (lambda ()
                                  (:mime rc
                                         `((message unquote message))))))))))
