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

(in-package :roslisp)


(defun start-ros-node (name &key (xml-rpc-port 8001 xml-port-supp) (pub-server-port 7001 pub-port-supp) 
                       (master-uri (make-uri "127.0.0.1" 11311) master-supplied) 
                       (anonymous nil) (cmd-line-args (rest sb-ext:*posix-argv*))
                       &allow-other-keys)
  "Start up the ROS Node with the given name and master URI.  Reset any stored state left over from previous invocations.

MASTER-URI is either a string of the form http://foo:12345, or an object created using make-uri.  If MASTER-URI is not provided, use *default-master-uri*, and if that's nil (which it will be unless client code sets it), use the value of environment variable ROS_MASTER_URI.

ANONYMOUS, if non-nil, causes the current time to be appended to the node name (to make it unique).

XML-RPC-PORT and PUB-SERVER-PORT are no longer used.

CMD-LINE-ARGS is the list of command line arguments (defaults to argv minus its first element).  It can also be a string of space-separated arguments."

  (declare (string name) (type (or string uri) master-uri))
  (assert (not xml-port-supp) nil "start-ros-node no longer accepts the xml-rpc-port argument")
  (assert (not pub-port-supp) nil "start-ros-node no longer accepts the pub-server-port argument")
  (unless (eq *node-status* :shutdown)
    (warn "Before starting node, node-status equalled ~a instead of :shutdown.  Shutting the previous node invocation down now." *node-status*)
    (shutdown-ros-node))

  (when anonymous
    (mvbind (success s ms) (sb-unix:unix-gettimeofday)
      (declare (ignore success))
      (setq name (format nil "~a_~a_~a" name ms s))))

  ;; check for legal base name once all changes have been made to the name
  (unless (and (alpha-char-p (char name 0))
               (every #'(lambda (c) (or (alphanumericp c) (equal c #\_))) name))
    (warn "~a is not a legal ROS base name. This may cause problems with other ROS tools" name))

  (let ((params (handle-command-line-arguments name cmd-line-args)))

    (setq *ros-log-location* (get-ros-log-location name))
    (ensure-directories-exist *ros-log-location* :verbose nil)
    (setq *ros-log-stream* (open *ros-log-location* :direction :output :if-exists :overwrite 
                                 :if-does-not-exist :create))
    

    ;; Deal with the master uri 
    (unless master-supplied      
      (setq master-uri (or *default-master-uri* (sb-ext:posix-getenv "ROS_MASTER_URI")))
      (unless (and (stringp master-uri) (> (length master-uri) 0))
        (error "Master uri needs to be supplied either as an argument to start-ros-node, or through the environment variable ROS_MASTER_URI, or by setting the lisp variable *default-master-uri*")))

    (when (stringp master-uri)
      (mvbind (address port) (parse-uri master-uri)
        (setq master-uri (make-uri address port))))

    (symbol-macrolet ((address (uri-address master-uri)))
      (unless (parse-string-ip-address address)
        (setf address (ip-address-string (lookup-hostname-ip-address address)))))

    (setq *master-uri* master-uri)
    
    ;; Set params specified at command line
    (dolist (p params)
      (set-param (car p) (cdr p)))

    ;; Initialize debug levels

    (reset-debug-levels (make-instance 'Empty-Request))

    ;; Now we can finally print some debug messages 
    (ros-debug (roslisp top) "Log location is ~a" *ros-log-location*)
    (command-line-args-rosout cmd-line-args params)
    (unless master-supplied (ros-debug (roslisp top) "Master uri was not supplied, so using default"))
    (ros-info (roslisp top) "master URI is ~a:~a" (uri-address master-uri) (uri-port master-uri))
    
    ;; Done setting up master connection
    

    ;; Spawn a thread that will start up the listeners, then run the event loop
    (with-recursive-lock (*ros-lock*)
      (setf *event-loop-thread*
      (sb-thread:make-thread 
       #'(lambda ()

           (when (eq *node-status* :running) 
             (error "Can't start node as status already equals running.  Call shutdown-ros-node first."))


           ;; Start publication and xml-rpc servers.  
           (mvbind (srv sock) (start-xml-rpc-server :port 0)
             (setq *xml-server* srv
                   xml-rpc-port (nth-value 1 (sb-bsd-sockets:socket-name sock))))
           (ros-debug (roslisp top) "Started XML-RPC server on port ~a" xml-rpc-port)

           (setq *tcp-server-hostname* (hostname)
                 *tcp-server* (ros-node-tcp-server 0)
                 pub-server-port (nth-value 1 (sb-bsd-sockets:socket-name *tcp-server*)))
           (ros-debug (roslisp top) "Started tcpros server on port ~a" pub-server-port)

           
           (setq *tcp-server-port* pub-server-port
                 *broken-socket-streams* (make-hash-table :test #'eq)
                 *service-uri* (format nil "rosrpc://~a:~a" *tcp-server-hostname* *tcp-server-port*)
                 *xml-rpc-caller-api* (format nil "http://~a:~a" (hostname) xml-rpc-port)
                 *publications* (make-hash-table :test #'equal)
                 *subscriptions* (make-hash-table :test #'equal)
                 *services* (make-hash-table :test #'equal)
                 *node-status* :running
                 *deserialization-threads* nil
                 )

           (pushnew #'maybe-shutdown-ros-node sb-ext:*exit-hooks*)

           ;; Finally, start the serve-event loop
           (event-loop))
       :name "ROSLisp event loop"))

      ;; There's no race condition - if this test and the following advertise call all happen before the event-loop starts,
      ;; things will just queue up
      (spin-until (eq *node-status* :running) 1))

    ;; Advertise on global rosout topic for debugging messages
    (advertise "/rosout" "rosgraph_msgs/Log")

    ;; Subscribe to time if necessary
    (setq *use-sim-time* (member (get-param "/use_sim_time" nil) '("true" 1 t) :test #'equal))
    (when *use-sim-time*
      (setq *last-clock* nil)
      (subscribe "/clock" "rosgraph_msgs/Clock" #'(lambda (m) (setq *last-clock* m))
                 :max-queue-length 5))

    ;; Advertise reset-debug-levels service
    (register-service-fn "~reset_debug_levels" #'reset-debug-levels 'Empty)
    
    (ros-info (roslisp top) "Node startup complete")))


(defmacro with-ros-node (args &rest body)
  "with-ros-node ARGS &rest BODY.  
Call start-ros-node with argument list ARGS, then execute the body.  Takes care of shutting down the ROS node if the body terminates or is interrupted.  

In addition to the start-ros-node arguments, ARGS may also include the boolean argument :spin.  If this is true, after body is executed, the node will just spin forever.

Assuming spin is not true, this call will return the return value of the final statement of body."

  (dbind (name &rest a &key spin &allow-other-keys) args
    (declare (ignorable name a))
    `(let (*namespace*) ;; Set up a binding so that start-ros-node can set it and this will be seen in the body, but not by our caller
       (unwind-protect
            (restart-case 
                (progn
                  (start-ros-node ,@args)
                  ,@body
                  ,@(when spin `((spin-until nil 100))))
              (shutdown-ros-node (&optional a) (ros-info (roslisp top) "About to shutdown~:[~; due to condition ~:*~a~]" a)))
         (shutdown-ros-node)))))


(defun shutdown-ros-node ()
  "Shutdown-ros-node.  Set the status to shutdown, close all open sockets and XML-RPC servers, and unregister all publications, subscriptions, and services with master node.  Finally, if *running-from-command-line* is true, exit lisp."
  (ros-debug (roslisp top) "Acquiring lock")
  (with-recursive-lock (*ros-lock*)
    (unless (eq *node-status* :shutdown)
      (ros-debug (roslisp top) "Initiating shutdown")
      (setf *node-status* :shutdown)
      (handler-case
          (stop-server *xml-server*)
        (error (c)
          (cerror "Continue" "Error stopping xml-rpc server: ~a" c)))
      (close-socket *tcp-server*)

      ;; Unregister from publications and subscriptions and close the sockets and kill callback and deserialization threads
      (do-hash (topic pub *publications*)
        (protected-call-to-master ("unregisterPublisher" topic *xml-rpc-caller-api*) c
          (ros-warn (roslisp) "Could not contact master at ~a when unregistering as publisher of ~a during shutdown: ~a" *master-uri* topic c))
        
        
        (dolist (sub (subscriber-connections pub))
          (handler-case
              (close-socket (subscriber-socket sub))
            (sb-int:simple-stream-error (c)
              (ros-debug (roslisp top) "Received stream error ~a when attempting to close socket ~a.  Skipping." c (subscriber-socket sub))))))

      (do-hash (topic sub *subscriptions*)
        (protected-call-to-master ("unregisterSubscriber" topic *xml-rpc-caller-api*) c
          (ros-warn (roslisp) "Could not contact master when unsubscribing from ~a during shutdown: ~a" topic c))
        (handler-case (terminate-thread (topic-thread sub))
          (interrupt-thread-error (e)
            (declare (ignore e)))))

      (dolist (thread *deserialization-threads*)
        (ros-debug (roslisp deserialization-thread) "Killing deserialization thread")
        (ignore-errors (terminate-thread thread)))

      ;; Unregister services
      (do-hash (name s *services*)
        (let ((i (protected-call-to-master ("unregisterService" name *service-uri*) c
                   (ros-warn roslisp "During shutdown, unable to contact master to unregister service ~a: ~a" name c)
                   1)))
          (unless (eql i 1)
            (ros-warn (roslisp top) "When trying to close service ~a, ~a services were closed instead of 1" name i))))

      ;; Unset variables that will be used upon next startup
      (setq *ros-log-location* nil)

      ;; wait nicely for end of event loop, which was notified by setting *node-status* to shutdown
      (dotimes (wait-it 6)
        (when (sb-thread:thread-alive-p *event-loop-thread*)
          (sleep 0.5)))
      (when (sb-thread:thread-alive-p *event-loop-thread*)
        ;; try killing event-loop thread (may take time)
        (sb-thread:terminate-thread *event-loop-thread*)
        (dotimes (wait-it 6)
          (when (sb-thread:thread-alive-p *event-loop-thread*)
            (sleep 0.5))))
      (when (sb-thread:thread-alive-p *event-loop-thread*)
        (error "Event-loop thread cannot be terminated"))
      (setf *event-loop-thread* nil)
      
      (ros-info (roslisp top) "Shutdown complete")
      (close *ros-log-stream*)
      (when *running-from-command-line* (sb-ext:exit)))))

(defun maybe-shutdown-ros-node ()
  (unless (eq *node-status* :shutdown)
    (shutdown-ros-node)))

