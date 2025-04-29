;;; pingwing -- the free and open Lisp-powered notification nexus

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
  #:use-module (ice-9 iconv)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 string-fun)
  #:use-module (json)
  #:use-module (artanis db)
  #:use-module (artanis ssql)
  #:use-module (srfi srfi-64)
  #:use-module (pingwing process)
  #:use-module (pingwing templates password-reset)
  #:use-module (pingwing query-escape)
  #:use-module (app models task))

(define* (pingwing-send-mail #:key id
                             access-key
                             access-secret
                             access-server
                             access-port
                             from-name
                             from-address
                             to-name
                             to-address
                             subject
                             body
                             body-html)

  
  (let* ((html-file (format #f "tmp/~a/~a-~a-body.html" id from-address to-address))
         (text-file (format #f "tmp/~a/~a-~a-body.txt" id from-address to-address))
         (_ (with-output-to-file html-file
              (lambda() (display body-html))))
         (_ (with-output-to-file text-file
              (lambda() (display body))))
         (cmd (format #f
                      (string-join '("curl --verbose --ssl-reqd"
                                     "--url smtp://~a:~a"
                                     "--user \"~a:~a\""
                                     "--mail-from '~a'"
                                     "--mail-rcpt '~a'"
                                     "--mail-rcpt-allowfails"
                                     ;; headers
                                     "-H \"From: \"~a\" <~a>\""
                                     "-H \"To: \"~a\" <~a>\""
                                     "-H \"Subject: ~a\""
                                     ;; "-H \"Reply-To: ~a\""
                                     ;; form
                                     "-F '=(;type=multipart/alternative'"
                                     "-F \"=<~a;encoder=quoted-printable\""
                                     "-F \"=<~a;encoder=quoted-printable\""
                                     "-F '=)'") " ")
                      access-server
                      access-port
                      access-key
                      access-secret

                      from-address
                      to-address
                      from-name
                      from-address
                      to-name
                      to-address
                      subject

                      html-file
                      text-file

                      )))
    (log-separator)
    (log-info (format #f "sending mail to ~a\n" access-server))
    (display cmd)))

(define* (body-from-task #:key task)
  (display (string->symbol (assoc-ref task "template")))
  (let* ((v (json-string->scm (unescape-str (assoc-ref task "template_vars")))))
    (match (string->symbol (assoc-ref task "template"))
      ('password-reset (password-reset-plain-template #:system-name (assoc-ref
                                                                     v
                                                                     "system-name")
                                                      #:user (assoc-ref v
                                                              "user")
                                                      #:reset-link (assoc-ref
                                                                    v
                                                                    "reset-link")))
      (_ #f))))

(define* (html-body-from-task #:key task)
  (display (string->symbol (assoc-ref task "template")))
  (let* ((v (json-string->scm (unescape-str (assoc-ref task "template_vars")))))
    (match (string->symbol (assoc-ref task "template"))
      ('password-reset (password-reset-html-template #:system-name (assoc-ref
                                                                    v
                                                                    "system-name")
                                                     #:user (assoc-ref v
                                                                       "user")
                                                     #:reset-link (assoc-ref v
                                                                   "reset-link")))
      (_ #f))))

(define* (do-send-mail #:key task recipient pingwing-settings)
  (pingwing-send-mail #:id (assoc-ref task "id")
                      #:access-key (assoc-ref (assoc-ref pingwing-settings
                                                         'mail)
                                              'access-key)
                      #:access-secret (assoc-ref (assoc-ref pingwing-settings
                                                            'mail)
                                                 'access-secret)
                      #:access-server (assoc-ref (assoc-ref pingwing-settings
                                                            'mail)
                                                 'access-server)
                      #:access-port (assoc-ref (assoc-ref pingwing-settings
                                                          'mail)
                                               'access-port)
                      #:from-name (unescape-str (assoc-ref task "sender_name"))
                      #:from-address (unescape-str (assoc-ref task
                                                              "sender_address"))
                      #:to-name (assoc-ref recipient "name")
                      #:to-address (assoc-ref recipient "address")
                      #:subject (assoc-ref task "subject")
                      #:body (body-from-task #:task task)
                      #:body-html (html-body-from-task #:task task)))

(define (log-separator)
  (display "\n========================"))

(define (log-info msg)
  (display (format #f "\n>>= ~a\n" msg)))

(define* (pingwing-task-processor #:key task pingwing-settings)
  (let ((conn (get-conn-from-pool!)))
    (log-separator)
    (log-info (gettext "processing pingwing task"))
    (catch #t
           (lambda ()
             (mkdir (format #f "tmp/~a"
                            (assoc-ref task "id"))))
           (lambda (key . args)
             '()))
    (for-each (lambda (recipient)
                (do-send-mail #:recipient recipient
                              #:pingwing-settings pingwing-settings
                              #:task task))
              (vector->list (json-string->scm (unescape-str (assoc-ref task
                                                             "recipients")))))
    (DB-query conn
              (->sql update
                     'task set
                     `((task_status complete)
                       (updated_at ,(current-time)))
                     (where #:id (assoc-ref task "id"))))
    (DB-close conn)))

(define-public (pingwing-worker-thread pingwing-settings)
  (log-separator)
  (log-info (gettext "initializing pingwing queue worker"))

  (use-modules (pingwing tasks)
               (app models task))

  (catch #t
         (lambda ()
           (mkdir "tmp"))
         (lambda (key . args)
           '()))

  (while #t
         (let* ((next-task ($task 'get
                                  #:ret 1
                                  #:condition (where #:task_status "pending")
                                  #:order-by "created_at ASC"))
                (exception-handler (lambda (key . args)
                                     (display (format #f
                                               "\nerror processing task: ~a ~a"
                                               key args)))))
           (when (eq? (length next-task) 1)
             (catch #t
                    (lambda ()
                      (pingwing-task-processor #:task (car next-task)
                                               #:pingwing-settings
                                               pingwing-settings))
                    exception-handler))

           (sleep (assoc-ref (assoc-ref pingwing-settings
                                        'pingwing)
                             'worker-sleep-seconds)))))

