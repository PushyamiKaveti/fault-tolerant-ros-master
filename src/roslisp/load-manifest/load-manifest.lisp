;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Software License Agreement (BSD License)
;; 
;; Copyright (c) 2008, Willow Garage, Inc.
;; All rights reserved.
;;
;; Redistribution and use in source and binary forms, with 
;; or without modification, are permitted provided that the 
;; following conditions are met:
;;
;;  * Redistributions of source code must retain the above 
;;    copyright notice, this list of conditions and the 
;;    following disclaimer.
;;  * Redistributions in binary form must reproduce the 
;;    above copyright notice, this list of conditions and 
;;    the following disclaimer in the documentation and/or 
;;    other materials provided with the distribution.
;;  * Neither the name of Willow Garage, Inc. nor the names 
;;    of its contributors may be used to endorse or promote 
;;    products derived from this software without specific 
;;    prior written permission.
;; 
;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND 
;; CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED 
;; WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A 
;; PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
;; COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
;; INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
;; PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
;; CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
;; OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH 
;; DAMAGE.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defpackage :ros-load-manifest
    (:nicknames :ros-load)
  (:export :load-manifest :load-system :asdf-paths-to-add :*current-ros-package*
           :asdf-ros-search :asdf-ros-pkg-search :ros-package-path :ros-home :rospack)
  (:use :cl))

(in-package :ros-load-manifest)

(defvar *current-ros-package* nil
  "A string naming the current package.  This is used in the asdf-ros-search search method.")

(defvar *ros-asdf-output-cache* (make-hash-table :test 'eq))

(defvar *ros-asdf-paths-cache* (make-hash-table :test 'equal)
  "Cache of asdf directories returned by ASDF-PATHS-TO-ADD to reduce rospack calls.")

(defvar *ros-package-path-cache* (make-hash-table :test 'equal)
  "Cache for ros package paths.")

(defvar *ros-asdf-use-ros-home* nil)

(defconstant +marker-file-timeout+ 60.0)

(defun asdf-system-of-component (component)
  "Returns the system of a component."
  (typecase component
    (asdf:system component)
    (asdf:component (asdf-system-of-component (asdf:component-parent component)))))

(defun path-ros-package (path &optional traversed)
  "Traverses the `path' upwards until it finds a manifest.
   Returns two values, the name of the ros package and the relative
   part of path inside the package. Returns nil if no manifest could
   be found."
  (let ((manifest (probe-file (merge-pathnames "manifest.xml" path)))
        (marker-file (probe-file (merge-pathnames "roslisp_ignore" path))))
    (cond (marker-file nil)
          (manifest
           (values (truename path) traversed))
          ((not (cdr (pathname-directory path)))
           nil)
          (t
           (path-ros-package (make-pathname :directory (butlast (pathname-directory path)))
                             (cons (car (last (pathname-directory path)))
                                   traversed))))))

(defun asdf-system-ros-name (system)
  "Returns the ros package name of a system."
  (multiple-value-bind (package-path rel-path)
      (path-ros-package (asdf:component-pathname system))
    (assert (eq (car (pathname-directory package-path)) :absolute))
    (values (car (last (pathname-directory package-path))) rel-path)))

(defun pathname-rel-subdir (p1 p2)
  "returns the relative path of `p2' in `p1'."
  (loop with result = (pathname-directory  (truename p2))
        for d1 in (pathname-directory (truename p1))
        do (setf result (cdr result))
        finally (return result)))

(defun roslisp-home-output-files (component)
  "Returns the output filename of an asdf component inside ROS_HOME (or ~/.ros)."
  (let ((system (asdf-system-of-component component))
        (component-path (asdf:component-pathname component)))
    (destructuring-bind (package-name rel-path)
        (or (gethash system *ros-asdf-output-cache*)
            (setf (gethash system *ros-asdf-output-cache*)
                  (multiple-value-list (asdf-system-ros-name system))))
      (list
       (asdf::compile-file-pathname
        (merge-pathnames (make-pathname :name (pathname-name component-path)
                                        :type (pathname-type component-path)
                                        :directory `(:relative ,@(pathname-rel-subdir
                                                                  (asdf:component-pathname system)
                                                                  component-path)))
                         (merge-pathnames
                          (make-pathname :directory `(:relative "roslisp" ,package-name ,@rel-path))
                          (ros-home))))))))

;; Use lock file to prevent from parallel compilation of the same
;; system

(defun wait-for-file-deleted (file msg &optional delete-timeout)
  "Waits for `file' to be removed or, when `timeout' is set and
expires, deletes the file."
  (let ((timer (sb-ext:make-timer
                (lambda () (delete-file file)))))
    (when delete-timeout
      (sb-ext:schedule-timer timer delete-timeout))
    (unwind-protect
         (let ((print-msg t))
           (loop while (probe-file file) do
             (when print-msg
               (warn 'simple-warning :format-control msg)
               (setf print-msg nil))
             (sleep 0.5)))
      (when delete-timeout
        (sb-ext:unschedule-timer timer)))))

(defun compilation-marker-file-path (component)
  (merge-pathnames (make-pathname
                    :name (concatenate 'string
                                       ".roslisp-compile-"
                                       (asdf:component-name component)))
                   (ros-home)))

(defmethod asdf:perform :around ((op asdf:compile-op) component)
  (unless (typep component 'asdf:cl-source-file)
    (call-next-method)
    (return-from asdf:perform))
  (let ((marker-file-path (compilation-marker-file-path component)))
    (unwind-protect
         (tagbody
          retry
            (handler-bind
                ((file-error (lambda (e)
                               (declare (ignore e))
                               (wait-for-file-deleted
                                marker-file-path
                                (format nil
                                        "System `~a' is compiled by a different process. Waiting for compilation of blocking file to finish. Will proceed in at most ~a seconds."
                                        (asdf:component-name (asdf-system-of-component component))
                                        +marker-file-timeout+)
                                +marker-file-timeout+)
                               (go retry))))
              (close
               (open marker-file-path
                     :if-exists :error
                     :if-does-not-exist :create
                     :direction :output)))
            (call-next-method))
      (when (probe-file marker-file-path)
        (delete-file marker-file-path)))))

(defmethod asdf:perform :around ((op asdf:load-op) component)
  (unless (typep component 'asdf:cl-source-file)
    (call-next-method)
    (return-from asdf:perform))
  (let ((marker-file-path (compilation-marker-file-path component)))
    (wait-for-file-deleted marker-file-path
                           (format nil
                                   "System `~a' is compiled by a different process. Waiting for compilation of blocking file to finish."
                                   (asdf:component-name (asdf-system-of-component component))))
    (call-next-method)))

(defun ros-home ()
  (or (sb-ext:posix-getenv "ROS_HOME")
      (merge-pathnames (make-pathname :directory '(:relative ".ros"))
                       (user-homedir-pathname))))

(defun rospack (&rest cmd-args)
  (labels ((split-str (seq &optional (separator #\Newline))
             (labels ((doit (start-pos)
                        (let ((split-pos (position separator seq :start start-pos)))
                          (when split-pos
                            (cons (subseq seq start-pos split-pos)
                                  (doit (1+ split-pos)))))))
               (doit 0))))
    (let* ((str (make-string-output-stream))
           (error-str (make-string-output-stream))
           (proc (sb-ext:run-program "rospack" cmd-args :search t :output str :error error-str))
           (exit-code (sb-ext:process-exit-code proc)))
      (if (zerop exit-code)
          (split-str (get-output-stream-string str))
          (error "rospack ~{~a~^ ~} returned ~a with stderr '~a'" 
                 cmd-args exit-code (get-output-stream-string error-str))))))


(defun asdf-paths-to-add (package)
  "Given a package name, calls rospack to find out the dependencies. Adds all the /asdf directories that it finds to a list and return it."
  (let ((asdf-dir-list 
          (cons (get-asdf-directory (ros-package-path package))
                (loop for pkg in (or (gethash package *ros-asdf-paths-cache*)
                                     (setf (gethash package *ros-asdf-paths-cache*)
                                           (rospack "depends" package)))
                      for asdf-dir = (get-asdf-directory (ros-package-path pkg))
                      when asdf-dir collecting asdf-dir))))
    (remove nil asdf-dir-list)))

(defun normalize (str)
  (let* ((pos (position #\Newline str))
         (stripped (if pos
                       (subseq str 0 pos)
                       str)))
    (if (eq #\/ (char stripped (1- (length stripped))))
        stripped
        (concatenate 'string stripped "/"))))

(defun ros-package-path (p)
  (or (gethash p *ros-package-path-cache*)
      (setf (gethash p *ros-package-path-cache*)
            (pathname (normalize (first (rospack "find" p)))))))

(defun get-asdf-directory (path)
  (let ((asdf-path (merge-pathnames "asdf/" path)))
    (when (probe-file asdf-path) asdf-path)))

(defun asdf-ros-search (def &aux (debug-print (sb-ext:posix-getenv "ROSLISP_LOAD_DEBUG")))
  "An ASDF search method for ros packages.  When *current-ros-package*
is a nonempty string, it uses rospack to generate the list of
depended-upon packages, with the current one at the front.  It then
searches the asdf/ subdirectory of each package root in turn for the
package."
  (if (and (stringp *current-ros-package*) (> (length *current-ros-package*) 0))
      (let ((paths (asdf-paths-to-add *current-ros-package*)))
        (when debug-print (format t "~&Current ros package is ~a.  Searching for asdf system ~a in directories:~&    ~a" *current-ros-package* def paths))
        (dolist (p paths)
          (let ((filename (merge-pathnames (make-pathname :name def :type "asd") p)))
            (when (probe-file filename)
              (when debug-print (format t "~&  Found ~a" filename))
              (return-from asdf-ros-search filename))))
        (when debug-print (format t "~&  Not found")))
      (when debug-print (format t "~&asdf-ros-search not invoked since *current-ros-package* is ~a" *current-ros-package*))))

(asdf:initialize-source-registry
 (let ((roslisp-package-directories (sb-posix:getenv "ROSLISP_PACKAGE_DIRECTORIES"))
       (ros-package-path (sb-posix:getenv "ROS_PACKAGE_PATH"))
       ;; during the transition from asdf2 to asdf3 the utility function
       ;; 'split-string' moved from package 'asdf' to package 'uiop'.
       ;; Hence, the version-dependent function-call
       (split-string-symbol 
        (if (asdf:version-satisfies (asdf:asdf-version) "3.0") 
            (intern "SPLIT-STRING" :uiop)
            (intern "SPLIT-STRING" :asdf))))
   `(:source-registry
     ,@(when roslisp-package-directories
         (mapcan (lambda (path)
                   (when (and path (> (length path) 0))
                     `((:tree ,path))))
                 (funcall split-string-symbol roslisp-package-directories :separator '(#\:))))
     ,@(when ros-package-path
         (mapcan (lambda (path)
                   (when (and path (> (length path) 0))
                     `((:tree ,path))))
                 (funcall split-string-symbol ros-package-path :separator '(#\:))))
     ;; NOTE(lorenz): this looks to me as sort of an ugly hack but we
     ;; should not break the user's source registry
     ;; configuration. Instead, we inherit the user's configuration if
     ;; it exists and just add our entries at the beginning.
     ,@(if (and (boundp 'asdf:*source-registry-parameter*)
                (eq (car asdf:*source-registry-parameter*)
                    :source-registry))
           (cdr asdf:*source-registry-parameter*)
           (list :inherit-configuration)))))

(setq asdf:*system-definition-search-functions* 
      (append asdf:*system-definition-search-functions*
              '(asdf-ros-search)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; top level
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun load-manifest (package)
  "Walks down the tree of dependencies of this ros package.  Backtracks when it reaches a leaf or a package with no asdf/ subdirectory.  Adds all the asdf directories it finds to the asdf:*central-registry*."
  (cerror "continue" "Load manifest deprecated!")
  (dolist (p (asdf-paths-to-add package))
    (pushnew p asdf:*central-registry* :test #'equal)))

(defun load-system (package &optional (asdf-name package) force)
  "Sets *CURRENT-ROS-PACKAGE* and performs an asdf load operation on `package'"
  (let ((*current-ros-package* package))
    (asdf:operate 'asdf:load-op asdf-name :force force)))
