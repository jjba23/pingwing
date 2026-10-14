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

;;; Turning a task into a message, and a message into a delivery.
;;;
;;; Two things are kept apart here on purpose.  Building the message is a pure
;;; job -- headers, encodings, boundaries -- and it is done once per recipient,
;;; in front of the retry loop, so a retried delivery is retried as the very
;;; same bytes.  Sending is the part that talks to the world, and the only
;;; part that can fail in ways a caller has to hear about: a mail is reported
;;; as sent only when the SMTP server said it took it, and when it did not,
;;; what the server said is what the caller is handed back.
;;;
;;; The encoding is not decoration either.  A header with an accent in it, a
;;; body with a euro sign or a line long enough to be wrapped, all go through
;;; RFC 2047 and quoted-printable before they are written, so the bytes that
;;; arrive are the bytes intended rather than whatever the reader's client
;;; makes of raw UTF-8.  Nothing here trusts a value to be header-safe: every
;;; header is stripped of line breaks first, which is what stops a crafted
;;; subject from injecting headers of its own.

(define-module (pingwing mail)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 iconv)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (rnrs bytevectors)
  #:use-module ((rnrs io ports)
                #:hide (bytevector->string))
  #:use-module (uuid generate)
  #:use-module (curl)
  #:export (pingwing-send-mail build-mail-message
                               quoted-printable-encode
                               rfc2047-encode
                               rfc5322-date
                               format-address
                               sanitize-header))

;;; ---------------------------------------------------------------- encoding

;; base64 without pulling in a dependency: a header only ever asks for it over
;; the bytes of a UTF-8 string, so four characters per three bytes is all that
;; is needed.
(define base64-alphabet
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(define (base64-encode-bytes bv)
  "Base64-encode the bytevector BV, without line breaks."
  (let loop
    ((i 0)
     (acc '()))
    (if (>= i
            (bytevector-length bv))
        (apply string-append
               (reverse acc))
        (let* ((len (bytevector-length bv))
               (b0 (bytevector-u8-ref bv i))
               (b1 (if (< (+ i 1) len)
                       (bytevector-u8-ref bv
                                          (+ i 1)) 0))
               (b2 (if (< (+ i 2) len)
                       (bytevector-u8-ref bv
                                          (+ i 2)) 0))
               (n (+ (* b0 65536)
                     (* b1 256) b2))
               (rem (- len i))
               (chunk (string (string-ref base64-alphabet
                                          (quotient n 262144))
                              (string-ref base64-alphabet
                                          (modulo (quotient n 4096) 64))
                              (if (>= rem 2)
                                  (string-ref base64-alphabet
                                              (modulo (quotient n 64) 64)) #\=)
                              (if (>= rem 3)
                                  (string-ref base64-alphabet
                                              (modulo n 64)) #\=))))
          (loop (+ i 3)
                (cons chunk acc))))))

(define (ascii-only? s)
  (every (lambda (c)
           (< (char->integer c) 128))
         (string->list s)))

;; An RFC 2047 `encoded-word', which is what a header uses to carry anything
;; outside US-ASCII.  A header that is already ASCII is handed back untouched,
;; so the common case stays readable in the raw source.
(define (rfc2047-encode s)
  (if (ascii-only? s) s
      (format #f "=?UTF-8?B?~a?="
              (base64-encode-bytes (string->utf8 s)))))

;; A header value is single-line by definition.  Whatever a caller sends --
;; a subject, a display name -- anything that could start a header of its own
;; is turned into a space first.
(define (sanitize-header s)
  (if (string? s)
      (string-map (lambda (c)
                    (if (or (char=? c #\newline)
                            (char=? c #\return)) #\space c)) s) ""))

;; A byte's quoted-printable spelling.  FIRST? says whether it opens a
;; physical line -- a dot there becomes its escape, which is what keeps a body
;; line from being mistaken for SMTP's end-of-data marker; LAST? says whether
;; it ends one, where a space or tab has to be escaped because a transport is
;; allowed to eat it.
;; The two hex digits of a byte, upper case: `=C3', not `=c3'.  Written out
;; rather than left to `format' only because the reader of a diff and the
;; client decoding it should see the same, conventional spelling.
(define (qp-hex b)
  (string-append "="
                 (string-upcase (string-pad (number->string b 16) 2 #\0))))

(define (quoted-printable-byte b first? last?)
  (cond
    ((and first?
          (= b 46))
     "=2E")
    ((= b 61)
     "=3D")
    ((and last?
          (or (= b 32)
              (= b 9)))
     (qp-hex b))
    ((or (< b 32)
         (> b 126))
     (qp-hex b))
    (else (string (integer->char b)))))

;; The encoding runs over the UTF-8 bytes, not the characters: a `é' is two
;; bytes on the wire and has to be two escapes, or the reader is handed a
;; single byte that is not valid UTF-8 at all.  Only ASCII is ever left as
;; itself, which is exactly the range where a byte and a character agree.
(define (quoted-printable-encode text)
  "Quoted-printable-encode TEXT, with CRLF line endings throughout."
  (let* ((normalized (string-replace-substring (string-replace-substring (or
                                                                          text
                                                                          "")
                                                                         "\r\n"
                                                                         "\n")
                                               "\r" "\n"))
         (bytes (string->utf8 normalized))
         (len (bytevector-length bytes)))
    (let loop
      ((i 0)
       (col 0)
       (first? #t)
       (acc '()))
      (if (>= i len)
          (apply string-append
                 (reverse acc))
          (let ((b (bytevector-u8-ref bytes i)))
            (if (= b 10)
                (loop (+ i 1) 0 #t
                      (cons "\r\n" acc))
                (let* ((last? (or (>= (+ i 1) len)
                                  (= (bytevector-u8-ref bytes
                                                        (+ i 1)) 10)))
                       (token (quoted-printable-byte b first? last?))
                       (tlen (string-length token)))
                  (if (> (+ col tlen) 75)
                      ;; A soft break starts a physical line of its own, so the
                      ;; byte is spelled again as one that opens a line.
                      (let* ((token (quoted-printable-byte b #t last?))
                             (tlen (string-length token)))
                        (loop (+ i 1) tlen #t
                              (cons token
                                    (cons "=\r\n" acc))))
                      (loop (+ i 1)
                            (+ col tlen) #f
                            (cons token acc))))))))))

;;; ---------------------------------------------------------------- headers

(define day-names
  '#("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))
(define month-names
  '#("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

;; The date in the one format a mail header is allowed to use.  It is built by
;; hand rather than through strftime because strftime answers in the process's
;; locale, and a header has to read `14 Oct 2026' whatever language the host
;; happens to be set to.
(define (rfc5322-date)
  (let* ((t (localtime (current-time)))
         (off (tm:gmtoff t))
         (sign (if (<= off 0) "+" "-"))
         (ao (abs off)))
    (format #f
            "~a, ~2,'0d ~a ~4,'0d ~2,'0d:~2,'0d:~2,'0d ~a~2,'0d~2,'0d"
            (vector-ref day-names
                        (tm:wday t))
            (tm:mday t)
            (vector-ref month-names
                        (tm:mon t))
            (+ 1900
               (tm:year t))
            (tm:hour t)
            (tm:min t)
            (tm:sec t)
            sign
            (quotient ao 3600)
            (quotient (modulo ao 3600) 60))))

(define (quote-display-name name)
  "NAME as a header phrase: quoted when it holds a special, encoded when it
holds a non-ASCII character."
  (cond
    ((not (ascii-only? name))
     (rfc2047-encode name))
    ((string-any (lambda (c)
                   (memv c
                         (string->list "()<>@,;:\\\".[] "))) name)
     (format #f "\"~a\""
             (string-replace-substring (string-replace-substring name "\\"
                                                                 "\\\\") "\""
                                       "\\\"")))
    (else name)))

(define (format-address name address)
  "An address header value: `Name <address>', or a bare address with no name."
  (let ((name (sanitize-header (or name "")))
        (address (sanitize-header (or address ""))))
    (if (string-null? name) address
        (format #f "~a <~a>"
                (quote-display-name name) address))))

(define (domain-of address)
  "The part after the @ of ADDRESS, or a neutral placeholder when there is
none, which is what a generated Message-ID is tagged with."
  (or (and (string? address)
           (let ((at (string-rindex address #\@)))
             (and at
                  (substring address
                             (+ at 1)
                             (string-length address))))) "pingwing"))

;;; ------------------------------------------------------------- the message

(define* (build-mail-message #:key id
                             from-name
                             from-address
                             to-name
                             to-address
                             subject
                             body
                             body-html)
  "The whole RFC 5322 message for one recipient, as a string.

It is built once and, on a retry, sent unchanged: the boundary, the Date and
the Message-ID belong to the message, not to the attempt."
  (let* ((boundary (format #f "pingwing-~a"
                           (generate-string-uuid)))
         (message-id (format #f "~a@~a"
                             (generate-string-uuid)
                             (domain-of from-address)))
         (safe-subject (format #f "~a ~a"
                               (sanitize-header subject) id)))
    (string-append "MIME-Version: 1.0\r\n"
                   "Date: "
                   (rfc5322-date)
                   "\r\n"
                   "Message-ID: <"
                   message-id
                   ">\r\n"
                   "Subject: "
                   (rfc2047-encode safe-subject)
                   "\r\n"
                   "From: "
                   (format-address from-name from-address)
                   "\r\n"
                   "To: "
                   (format-address to-name to-address)
                   "\r\n"
                   "Content-Type: multipart/alternative; boundary=\""
                   boundary
                   "\"\r\n"
                   "\r\n"
                   "This is a message in MIME format.\r\n"
                   "\r\n"
                   "--"
                   boundary
                   "\r\n"
                   "Content-Type: text/plain; charset=\"UTF-8\"
"
                   "Content-Transfer-Encoding: quoted-printable
"
                   "\r\n"
                   (quoted-printable-encode body)
                   "\r\n"
                   "--"
                   boundary
                   "\r\n"
                   "Content-Type: text/html; charset=\"UTF-8\"
"
                   "Content-Transfer-Encoding: quoted-printable
"
                   "\r\n"
                   "<!DOCTYPE HTML>\r\n"
                   (quoted-printable-encode body-html)
                   "\r\n"
                   "--"
                   boundary
                   "--\r\n")))

;;; ------------------------------------------------------------- the sending

;; How many times one message is handed to the SMTP server before the attempt
;; is called a failure, and how long the first wait is.  Each wait doubles, so
;; three tries span about six seconds with a one-second base: enough for a
;; server that is restarting or a connection that blinks, and short enough
;; that a broken recipient is not held on to all day.  Both are overridden by
;; the task's settings.
(define default-attempts
  3)
(define default-retry-base-seconds
  3)

(define (curl-reason)
  (catch #t
         (lambda ()
           (let ((code (curl-error-code)))
             (and code
                  (not (zero? code))
                  (format #f "libcurl ~a~a" code
                          (let ((s (catch #t
                                          (lambda ()
                                            (curl-error-string))
                                          (lambda _
                                            #f))))
                            (if (and s
                                     (not (equal? s "")))
                                (format #f ": ~a" s) ""))))))
         (lambda _
           #f)))

(define (response-text r)
  (catch #t
         (lambda ()
           (let ((s (bytevector->string r "utf-8")))
             (if (and s
                      (not (string-null? (string-trim-both s))))
                 (string-trim-both s) #f)))
         (lambda _
           #f)))

(define (safe-file-name s)
  (string-map (lambda (c)
                (if (or (char-alphabetic? c)
                        (char-numeric? c)
                        (char=? c #\.)
                        (char=? c #\-)
                        (char=? c #\_)) c #\_))
              (or s "recipient")))

;; One delivery attempt: write the message out, hand it to libcurl over SMTP
;; and read back what happened.  The temporary file is removed whatever the
;; outcome, which is what keeps a long-lived worker from filling its disk.
(define* (deliver-once #:key message
                       access-key
                       access-secret
                       access-server
                       access-port
                       from-address
                       to-address
                       tmp-dir
                       (use-ssl 1)
                       (cainfo "/etc/ssl/certs/ca-certificates.crt")
                       (verbose #f))
  (let* ((the-file (format #f "~a/pingwing-~a-~a" tmp-dir
                           (generate-string-uuid)
                           (safe-file-name to-address)))
         (handle #f))
    (catch #t
           (lambda ()
             (dynamic-wind (lambda ()
                             (with-output-to-file the-file
                               (lambda ()
                                 (display message))))
                           (lambda ()
                             (set! handle
                                   (curl-easy-init))
                             (curl-easy-setopt handle
                                               'url
                                               (format #f "smtp://~a:~a"
                                                       access-server
                                                       access-port))
                             (when verbose
                               (curl-easy-setopt handle
                                                 'verbose #t))
                             (curl-easy-setopt handle
                                               'use-ssl use-ssl)
                             (when (and cainfo
                                        (file-exists? cainfo))
                               (curl-easy-setopt handle
                                                 'cainfo cainfo))
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
                                               'readdata
                                               (open-input-file the-file))
                             (curl-easy-setopt handle
                                               'upload #t)
                             (let* ((result (curl-easy-perform handle #t))
                                    (reason (curl-reason)))
                               (if reason
                                   (cons #f reason)
                                   (cons #t
                                         (or (response-text result)
                                          "the server accepted the message")))))
                           (lambda ()
                             (when handle
                               (catch #t
                                      (lambda ()
                                        (curl-easy-cleanup handle))
                                      (lambda _
                                        #t)))
                             (catch #t
                                    (lambda ()
                                      (delete-file the-file))
                                    (lambda _
                                      #t)))))
           (lambda (key . args)
             (catch #t
                    (lambda ()
                      (delete-file the-file))
                    (lambda _
                      #t))
             (cons #f
                   (format #f "~a ~s" key args))))))

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
                             body-html
                             (attempts default-attempts)
                             (retry-base-seconds default-retry-base-seconds)
                             (tmp-dir "tmp")
                             (use-ssl 1)
                             (verbose #f))
  "Send one message to one recipient and answer `(cons ok? detail)'.

Answers `(cons #t reply)' when the SMTP server took the message, with REPLY
being what it said, and `(cons #f detail)' when every try it was given failed,
with DETAIL naming the recipient, how many tries there were and the last
reason -- which is what a caller, an operator and a `last_error' column all
need to read at a glance.  Nothing here throws: a delivery is a value."
  (let* ((message (build-mail-message #:id id
                                      #:from-name from-name
                                      #:from-address from-address
                                      #:to-name to-name
                                      #:to-address to-address
                                      #:subject subject
                                      #:body body
                                      #:body-html body-html))
         (tries (max 1
                     (if (and attempts
                              (number? attempts)
                              (> attempts 0)) attempts 1))))
    (let loop
      ((left tries)
       (attempt 1)
       (last-reason "unknown"))
      (if (<= left 0)
          (cons #f
                (format #f
                        "could not deliver to <~a> after ~a ~a: ~a"
                        to-address
                        tries
                        (if (= tries 1) "attempt" "attempts")
                        last-reason))
          (let ((verdict (deliver-once #:message message
                                       #:access-key access-key
                                       #:access-secret access-secret
                                       #:access-server access-server
                                       #:access-port access-port
                                       #:from-address from-address
                                       #:to-address to-address
                                       #:tmp-dir tmp-dir
                                       #:use-ssl use-ssl
                                       #:verbose verbose)))
            (if (car verdict) verdict
                (begin
                  (when (> left 1)
                    (display (format #f "
sending to <~a> did not work: ~a
retrying in ~a seconds...
"
                                     to-address
                                     (cdr verdict)
                                     (* retry-base-seconds
                                        (expt 2
                                              (- attempt 1)))))
                    (sleep (* retry-base-seconds
                              (expt 2
                                    (- attempt 1)))))
                  (loop (- left 1)
                        (+ attempt 1)
                        (cdr verdict)))))))))
