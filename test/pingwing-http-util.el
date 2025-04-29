;;; pingwing-http-util.el --- P4 HTTP calls helper -*- lexical-binding: t -*-

;; Package-Requires: ((request "0.3.3"))

;; Local Variables:
;; byte-compile-warnings: (not free-vars unresolved)
;; End:

;;; Commentary:

;; Using Emacs and request.el we can make our life easier and execute HTTP requests directly from Emacs
;; and post or pre-process data easily

;;; Code:

(defun pingwing-get-tasks ()
  "Get tasks in pingwing."
  (let* ((host "http://localhost:50077"))
    (request (string-join `(,host
                            "/api/v1/tasks"))
      :success (cl-function
                (lambda (&key response &allow-other-keys)
                  (message "Done: %s" (request-response-status-code response))
                  (sss-new-buffer-with-json (format "pingwing-http-util-%s" (sss-uuidgen-string))
                                            (request-response-data response))))
      :error (lambda (&key error &allow-other-keys)
               (message "Error: %s" error)))))

(pingwing-get-tasks)

(provide 'pingwing-http-util)

;;; pingwing-http-util.el ends here
