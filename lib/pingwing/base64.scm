;; pingwing - the free and open Lisp-powered notification nexus
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

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
