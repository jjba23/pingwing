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
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 string-fun)
  #:use-module (json)
  #:use-module (artanis db)
  #:use-module (artanis ssql)
  #:use-module (srfi srfi-64)
  #:use-module (pingwing process)
  #:use-module (pingwing query-escape)
  #:use-module (app models task))

(define* (pingwing-send-mail #:key access-key
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
  (let* ((cmd (format #f
                      (string-join '("curl -v --url smtp://~a:~a" "--ssl-reqd"
                                     "--mail-from '~a'"
                                     "--mail-rcpt '~a'"
                                     "--user ~a:~a"
                                     "-F '=(;type=multipart/alternative'"
                                     "-F '=~a'"
                                     "-F '= ~a;type=text/html'"
                                     "-F '=)'"
                                     ;; "-F 'file=@~a;type=~a;encoder=base64'"
                                     "-H \"Subject: ~a\""
                                     "-H \"From: ~a <~a>\""
                                     "-H \"To: ~a <~a>\"") " ")
                      access-server
                      access-port
                      from-address
                      to-address
                      access-key
                      access-secret
                      body
                      (escape-str body-html)
                      ;; attachments
                      ;; file
                      ;; "some-file.txt"
                      ;; mime
                      ;; "text/plain"
                      subject
                      from-name
                      from-address
                      to-name
                      to-address)))
    (display (format #f "\nsending mail to ~a\n" access-server))
    (display cmd)))

(define* (do-send-mail #:key task recipient pingwing-settings)
  (pingwing-send-mail #:access-key (assoc-ref (assoc-ref pingwing-settings
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
                      #:to-name (car (string-split recipient #\^))
                      #:to-address (cadr (string-split recipient #\^))
                      #:subject (assoc-ref task "subject")
                      #:body (assoc-ref task "body")
                      #:body-html "<h1>PRETTY</h1>"))

(define (log-separator)
  (display "\n\n========================\n"))

(define (log-info msg)
  (display (format #f ">>= ~a" msg)))

(define* (pingwing-task-processor #:key task pingwing-settings)
  (let ((conn (get-conn-from-pool!)))
    (log-separator)
    (log-info "processing pingwing task")

    (for-each (lambda (recipient)
                (do-send-mail #:recipient recipient
                              #:pingwing-settings pingwing-settings
                              #:task task))
              (vector->list (json-string->scm (unescape-str (assoc-ref
                                                             task
                                                             "recipients")))))
    (DB-query conn
              (->sql update
                     'task set
                     `((task_status complete)
                       (updated_at ,(current-time)))
                     (where #:id (assoc-ref task "id"))))
    (DB-close conn)))

(define-public (pingwing-worker-thread pingwing-settings)
  (display (format #f "\n~a...\n"
                   (gettext "initializing pingwing queue worker")))

  (use-modules (pingwing tasks)
               (app models task))

  (while #t
    (let* ((next-task ($task 'get
                             #:ret 1
                             #:condition (where #:task_status
                                                "pending")
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

