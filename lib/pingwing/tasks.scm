;;; pingwing -- the free and open Lisp-powered notification nexus

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
  #:use-module (curl)
  #:use-module (web response)
  #:use-module (kracht prelude)
  #:use-module (pingwing base64)
  #:use-module (pingwing templates password-reset)
  #:use-module (pingwing templates system-alert)
  #:use-module (pingwing query-escape)
  #:use-module (ice-9 pretty-print)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:use-module (artanis artanis)
  #:use-module (web request)
  #:use-module (web uri)
  #:use-module (pingwing sqlite task)
  #:use-module (pingwing domain task)
  #:export (pingwing-send-mail pingwing-worker-thread pingwing-task-processor
                               do-send-mail body-from-taqsk
                               html-body-from-task))

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
  
  (let* ((unico (format #f "~a-~a-~a" id from-address to-address))
         (the-file (format #f "tmp/~a" unico))
         (multipart-boundary
          "pingwing-message-multipart-boundary-33c2b557-7f27-4339-9a85-2385e7ecde9b")
         (_ (with-output-to-file the-file
              (lambda ()
                (display (string-join `("MIME-Version: 1.0" ,(format #f
                                                              "Subject: ~a ~a"
                                                              subject id)
                                        ,(format #f "From: ~a <~a>" from-name
                                                 from-address)
                                        ,(format #f "To: ~a <~a>" to-name
                                                 to-address)
                                        ;; TODO reply-to, cc, bcc
                                        ,(format #f
                                          "Content-Type: multipart/alternative; boundary=\"~a\""
                                          multipart-boundary)
                                        ""
                                        ,(format #f "--~a" multipart-boundary)
                                        "Content-Type: text/plain; charset=\"UTF-8\""
                                        "Content-Transfer-Encoding: quoted-printable"
                                        ""
                                        ,body
                                        ""
                                        ,(format #f "--~a" multipart-boundary)
                                        "Content-Type: text/html; charset=\"UTF-8\""
                                        "Content-Transfer-Encoding: quoted-printable"
                                        ""
                                        "<!DOCTYPE HTML>"
                                        ,body-html
                                        ""
                                        ,(format #f "--~a--"
                                                 multipart-boundary)) "\n")))))
         (file-port (open-input-file the-file))
         (handle (curl-easy-init))
         (_ (begin
              (curl-easy-setopt handle
                                'url
                                (format #f "smtp://~a:~a" access-server
                                        access-port))
              (curl-easy-setopt handle
                                'verbose #t)
              (curl-easy-setopt handle
                                'use-ssl 1)
              (curl-easy-setopt handle
                                'username access-key)
              (curl-easy-setopt handle
                                'password access-secret)
              (curl-easy-setopt handle
                                'mail-from from-address)
              (curl-easy-setopt handle
                                'mail-rcpt
                                (list to-address))
              (curl-easy-setopt handle
                                'readdata file-port)
              (curl-easy-setopt handle
                                'upload #t)))
         (r (curl-easy-perform handle #t))
         (rr (catch #t
                    (lambda ()
                      (bytevector->string r "utf-8"))
                    (lambda (key . args)
                      r))))
    (display rr)))

(define* (body-from-task #:key task)
  (let* ((v (json-string->scm (unescape-str (assq-ref task
                                                      'template-vars)))))
    (match (string->symbol (assq-ref task
                                     'template))
      ('password-reset (password-reset-plain-template #:system-name (assoc-ref
                                                                     v
                                                                     "system-name")
                                                      #:user (assoc-ref v
                                                              "user")
                                                      #:reset-link (assoc-ref
                                                                    v
                                                                    "reset-link")))
      ('system-alert (system-alert-plain-template #:system-name (assoc-ref v
                                                                 "system-name")
                                                  #:alert-value (assoc-ref v
                                                                 "alert-value")))
      (_ #f))))

(define* (html-body-from-task #:key task)
  (let* ((v (json-string->scm (unescape-str (assq-ref task
                                                      'template-vars)))))
    (match (string->symbol (assq-ref task
                                     'template))
      ('password-reset (password-reset-html-template #:system-name (assoc-ref
                                                                    v
                                                                    "system-name")
                                                     #:user (assoc-ref v
                                                                       "user")
                                                     #:reset-link (assoc-ref v
                                                                   "reset-link")))
      ('system-alert (system-alert-html-template #:system-name (assoc-ref v
                                                                "system-name")
                                                 #:alert-value (assoc-ref v
                                                                "alert-value")))
      (_ #f))))

(define* (do-send-mail #:key task recipient settings)
  (pingwing-send-mail #:id (assq-ref task
                                     'id)
                      #:access-key (assoc-ref (assoc-ref settings
                                                         'mail)
                                              'access-key)
                      #:access-secret (assoc-ref (assoc-ref settings
                                                            'mail)
                                                 'access-secret)
                      #:access-server (assoc-ref (assoc-ref settings
                                                            'mail)
                                                 'access-server)
                      #:access-port (assoc-ref (assoc-ref settings
                                                          'mail)
                                               'access-port)
                      #:from-name (unescape-str (assq-ref task
                                                          'sender-name))
                      #:from-address (unescape-str (assq-ref task
                                                             'sender-address))
                      #:to-name (assoc-ref recipient "name")
                      #:to-address (assoc-ref recipient "address")
                      #:subject (assq-ref task
                                          'subject)
                      #:body (body-from-task #:task task)
                      #:body-html (html-body-from-task #:task task)))

(define* (pingwing-task-processor #:key task-repo task settings)
  (log-info (gettext "processing pingwing task"))
  (for-each (lambda (recipient)
              (do-send-mail #:recipient recipient
                            #:settings settings
                            #:task task))
            (vector->list (json-string->scm (unescape-str (assq-ref task
                                                                    'recipients)))))
  (update-task-by-id task-repo
                     (assq-ref task
                               'id)
                     `((task-status . complete) (updated-at unquote
                                                            (current-time)))))

(define* (pingwing-worker-thread #:key task-repo settings)
  (log-info (gettext "initializing pingwing queue worker"))

  (catch #t
         (lambda ()
           (mkdir "tmp"))
         (lambda (key . args)
           '()))

  (while #t
         (let* ((task (get-next-pending-task task-repo))
                (exception-handler (lambda (key . args)
                                     (display (format #f
                                               "\nerror processing task: ~a ~a"
                                               key args)))))
           
           (catch #t
                  (lambda ()
                    (when (not (nil? task))
                      (pingwing-task-processor #:task-repo task-repo
                                               #:task task
                                               #:settings settings)))
                  exception-handler)

           (sleep (assoc-ref (assoc-ref settings
                                        'pingwing)
                             'worker-sleep-seconds)))))

