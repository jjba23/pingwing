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

(define-module (pingwing query-escape)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 iconv))

(define escape-alist
  '(("'" "&apos;")
    ("\"" "&quot;")))

(begin
  (define* (escape-str str
                       #:key (dict escape-alist))
    (define result
      str)
    (for-each (lambda (p)
                (set! result
                      (string-replace-substring result
                                                (car p)
                                                (car (cdr p))))) dict) result)
  (export escape-str))

(begin
  (define* (unescape-str str
                         #:key (dict escape-alist))
    (define result
      str)
    (for-each (lambda (p)
                (set! result
                      (string-replace-substring result
                                                (car (cdr p))
                                                (car p)))) dict) result)
  (export unescape-str))

