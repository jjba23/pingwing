;; pingwing - the free and open Lisp-powered notification nexus
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

(define-module (pingwing templates password-reset)
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
  #:export (password-reset-html-template password-reset-plain-template))

(define* (password-reset-html-template #:key system-name user reset-link)
  (let* ((tree (mail-document #:title (gettext "Password Reset")
                              #:content `((h1 (@ (class . "pw-heading")
                                                 (style ,(mail-heading-style)))
                                              ,(format #f "~a ~a"
                                                       (gettext
                                                        "Reset your password")
                                                       (or system-name "")))
                                          (p (@ (class . "pw-text")
                                                (style ,(mail-text-style)))
                                             ,(gettext
                                               "We received a request to reset the password for your account. If that was you, follow the button below; the link is yours alone, and it is safe to ignore this message if it was not."))
                                          ,(mail-inner (list (mail-facts (list
                                                                          (cons
                                                                           (gettext
                                                                            "Account")
                                                                           (mail-mono
                                                                            (or
                                                                             user
                                                                             "")))))))
                                          ,(mail-button #:href (or reset-link
                                                                   "#")
                                                        #:label (gettext
                                                                 "Reset your password"))
                                          (p (@ (class . "pw-muted")
                                                (style ,(mail-muted-style)))
                                             ,(gettext
                                               "If the button does not work, copy and paste this link into your browser:"))
                                          (p (@ (class . "pw-mono")
                                                (style ,(mail-mono-style)))
                                             ,(or reset-link ""))
                                          ,(mail-rule)
                                          (p (@ (class . "pw-muted")
                                                (style ,(mail-muted-style)))
                                             ,(gettext
                                               "This message was sent because someone asked to reset the password on this account. If that was not you, no action is needed and your password has not changed.")))))
         (_ tree))
    (mail-document->string tree)))

(define* (password-reset-plain-template #:key system-name user reset-link)
  (let* ((content (list (format #f "~a ~a"
                                (gettext "Reset your password:")
                                (or system-name ""))
                        ""
                        (gettext
                         "We received a request to reset the password for your account:")
                        (format #f "~a ~a"
                                (gettext "Account:")
                                (or user ""))
                        ""
                        (gettext "Follow this link to choose a new password:")
                        (or reset-link "")
                        ""
                        "----------------------------------"
                        (gettext
                         "If you did not ask for this, you can ignore this message.")
                        (gettext
                         "If you had trouble clicking the link, copy and paste it:")
                        (or reset-link "")
                        "----------------------------------"
                        (gettext
                         "this e-mail was powered by pingwing - the free and open Lisp-powered notification nexus")
                        "https://codeberg.org/jjba23/pingwing"
                        (gettext "see pingwing's source code on Codeberg"))))
    (string-join content "\n")))
