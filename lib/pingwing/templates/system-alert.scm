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
  #:use-module (sxml simple)
  #:use-module (ice-9 iconv)
  #:export (system-alert-html-template system-alert-plain-template))

(define* (system-alert-html-template #:key system-name alert-value)
  (let* ((tree (mail-document
                #:title (gettext "System Alert")
                #:content `((h1 (@ (class . "pw-heading")
                                   (style ,(mail-heading-style)))
                                ,(format #f "~a ~a"
                                         (gettext "System alert")
                                         (or system-name "")))
                            (p (@ (class . "pw-text")
                                  (style ,(mail-text-style)))
                               ,(gettext
                                 "An alert has been triggered from a system you watch. The details are below."))
                            ,(mail-inner
                              (list `(div (@ (class . "pw-mono")
                                             (style ,(mk-style
                                                      `(("font-family" . ,mail-mono-stack)
                                                        ("font-size" . "13px")
                                                        ("color" . ,(color-of
                                                                     mail-light
                                                                     'heading))
                                                        ("white-space" . "pre-wrap")
                                                        ("word-break" . "break-word")))))
                                          ,(or alert-value ""))))
                            ,(mail-rule)
                            (p (@ (class . "pw-muted")
                                  (style ,(mail-muted-style)))
                               ,(gettext
                                 "This message was sent automatically; reply to it if the alert needs a human.")))))
         (_ tree))
    (with-output-to-string (lambda ()
                             (sxml->xml tree)))))

(define* (system-alert-plain-template #:key system-name alert-value)
  (let* ((content (list (format #f "~a ~a"
                                (gettext "System Alert:")
                                (or system-name ""))
                        ""
                        (gettext "An alert has been triggered from your system:")
                        "----------------------------------"
                        (or alert-value "")
                        "----------------------------------"
                        (gettext
                         "this e-mail was powered by pingwing - the free and open Lisp-powered notification nexus")
                        "https://codeberg.org/jjba23/pingwing"
                        (gettext "see pingwing's source code on Codeberg"))))
    (string-join content "\n")))
