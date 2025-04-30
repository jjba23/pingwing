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
  #:use-module (sxml simple)
  #:use-module (ice-9 iconv))

(begin
  (define* (password-reset-html-template #:key system-name user reset-link)
    (let* ((tree `((html (head ,meta-charset
                               ,meta-ie
                               ,meta-responsive
                               ,meta-color-scheme
                               ,meta-supported-color-schemes
                               (title ,(gettext "Password Reset"))
                               (style ,mail-style))
                         (body (div (h1 (span ,(gettext
                                                "Reset your password: "))
                                        (span ,system-name))
                                    (p ,(gettext
                                         "We have received a request to reset the password for your user account:"))
                                    (dl (dt ,(gettext "User:"))
                                        (dd ,user))
                                    (a (@ (class . "button-link")
                                          (href unquote reset-link))
                                       ,(gettext "🔗 Reset your password on ")
                                       ,system-name)
                                    (hr)
                                    (p ,(gettext
                                         "Feel free to ignore this e-mail if you did not request it."))
                                    (p ,(gettext
                                         "If you had trouble clicking that link, please manually copy paste it:"))
                                    (p ,reset-link)
                                    ,mail-footer))))))
      (with-output-to-string (lambda ()
                               (sxml->xml tree)))))
  (export password-reset-html-template))

(begin
  (define* (password-reset-plain-template #:key system-name user reset-link)
    (let* ((content (list (gettext "Reset your password: ")
                          (gettext
                           "We have received a request to reset the password for your user account:")
                          (gettext "User:")
                          user
                          (gettext "Go reset your password on ")
                          system-name
                          reset-link
                          "----------------------------------"
                          (gettext
                           "Feel free to ignore this e-mail if you did not request it.")
                          (gettext
                           "If you had trouble clicking that link, please manually copy paste it:")
                          reset-link
                          "----------------------------------"
                          (gettext
                           "this e-mail was powered by pingwing - the free and open Lisp-powered notification nexus")
                          "https://codeberg.org/jjba23/pingwing"
                          (gettext "see pingwing's source code on Codeberg"))))
      (string-join content "\n")))
  (export password-reset-plain-template))
