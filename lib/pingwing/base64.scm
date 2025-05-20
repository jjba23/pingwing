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

(define-module (pingwing base64)
  #:use-module (artanis security nss))

(define-public (safe-base64-encode s)
  (cond
    ((not (equal? "" s))
     (nss:base64-encode s))
    (else s)))

(define-public (safe-base64-decode s)
  (catch #t
         (lambda ()
           (cond
             ((not (equal? "" s))
              (nss:base64-decode s))
             (else s)))
         (lambda (key . args)
           (display (format #f "error ocurred decoding string: ~a ~a" key args))
           s)))
