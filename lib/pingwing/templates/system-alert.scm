;; pingwing - the free and open Lisp-powered notification nexus
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

(define-module (pingwing templates system-alert)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64)
  #:use-module (pingwing css)
  #:use-module (pingwing html)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 iconv)
  #:export (system-alert-html-template system-alert-plain-template))

(define* (system-alert-html-template #:key system-name alert-value)
  (let* ((tree (mail-document #:title (gettext "System Alert")
                              #:content `((h1 (@ (class . "pw-heading")
                                                 (style ,(mail-heading-style)))
                                              ,(format #f "~a ~a"
                                                       (gettext "System alert")
                                                       (or system-name "")))
                                          (p (@ (class . "pw-text")
                                                (style ,(mail-text-style)))
                                             ,(gettext
                                               "An alert has been triggered from a system you watch. The details are below."))
                                          ,(mail-inner (list `(div (@
                                                                      (class . "pw-alert")
                                                                      (style ,
                                                                             (style-of 'alert)))
                                                                   ,(or
                                                                     alert-value
                                                                     ""))))
                                          ,(mail-rule)
                                          (p (@ (class . "pw-muted")
                                                (style ,(mail-muted-style)))
                                             ,(gettext
                                               "This message was sent automatically; reply to it if the alert needs a human.")))))
         (_ tree))
    (mail-document->string tree)))

(define* (system-alert-plain-template #:key system-name alert-value)
  (let* ((content (list (format #f "~a ~a"
                                (gettext "System Alert:")
                                (or system-name ""))
                        ""
                        (gettext
                         "An alert has been triggered from your system:")
                        "----------------------------------"
                        (or alert-value "")
                        "----------------------------------"
                        (gettext
                         "this e-mail was powered by pingwing - the free and open Lisp-powered notification nexus")
                        "https://codeberg.org/jjba23/pingwing"
                        (gettext "see pingwing's source code on Codeberg"))))
    (string-join content "\n")))
