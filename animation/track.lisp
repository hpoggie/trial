(in-package #:org.shirakumo.fraf.trial)

(defstruct (animation-frame
            (:constructor make-frame (time curve)))
  (time 0.0 :type single-float)
  (curve NIL :type (function (T single-float) T)))

(defmethod print-object ((frame animation-frame) stream)
  (print-unreadable-object (frame stream :type T)
    (format stream "~a" (animation-frame-time frame))))

(defmethod clock ((frame animation-frame))
  (animation-frame-time frame))

(defmethod sample (target (frame animation-frame) time &key)
  (declare (optimize speed))
  (funcall (animation-frame-curve frame) target time))

(defclass animation-track (sequences:sequence standard-object)
  ((name :initarg :name :initform NIL :accessor name)
   (value-type :initarg :value-type :accessor value-type)
   (frames :initform #() :accessor frames)
   (interpolation :initarg :interpolation :initform :linear :accessor interpolation)))

(defmethod shared-initialize :after ((track animation-track) slots &key times values frames)
  (cond ((and times values)
         (setf (frames track) (cons times values)))
        (frames
         (setf (frames track) frames))))

(defmethod print-object ((track animation-track) stream)
  (print-unreadable-object (track stream :type T)
    (if (valid-p track)
        (format stream "~a ~a" (start-time track) (end-time track))
        (format stream "INVALID"))))

(defgeneric start-time (track))
(defgeneric end-time (track))
(defgeneric duration (track))
(defgeneric sample (target track time &key))
(defgeneric find-frame-idx (track time loop-p))

(defmethod (setf frames) ((keyframes cons) (track animation-track))
  (destructuring-bind (times . values) keyframes
    (let ((frames (make-array (length times)))
          (j 0))
      (when (< 0 (length frames))
        (dotimes (i (length times))
          (setf (aref frames i)
                (make-frame (elt times i)
                            (ecase (interpolation track)
                              (:constant
                               (incf j)
                               (constant (elt values (1- j))))
                              (:linear
                               (incf j)
                               (linear (elt values (1- j)) (elt values j)))
                              (:hermite
                               (incf j 3)
                               (hermite (elt values (- j 2)) (elt values (- j 1))
                                        (elt values (+ j 1)) (elt values (+ j 0))))
                              (:bezier
                               ;; DATA is ordered like this: i0 v0 o0 i1 v1 o1
                               (incf j 3)
                               (bezier (elt values (- j 2)) (elt values (- j 1))
                                       (elt values (+ j 1)) (elt values (+ j 0))))
                              (:custom
                               (incf j)
                               (elt values (1- j)))))))
        (setf (value-type track) (type-of (elt values 0))))
      (setf (frames track) frames))))

(declaim (ftype (function (animation-track single-float boolean) single-float) fit-to-track))
(declaim (inline fit-to-track))
(defun fit-to-track (track time loop-p)
  (declare (optimize speed (safety 0)))
  (let ((frames (frames track)))
    (declare (type simple-vector frames))
    (declare (type single-float time))
    (if (<= (length frames) 1)
        0.0
        (let ((start (animation-frame-time (svref frames 0)))
              (end (animation-frame-time (svref frames (1- (length frames))))))
          (if loop-p
              (+ start (mod (- time start) (- end start)))
              (clamp start time end))))))

(defmethod valid-p ((track animation-track))
  (< 1 (length (frames track))))

(defmethod start-time ((track animation-track))
  (animation-frame-time (svref (frames track) 0)))

(defmethod end-time ((track animation-track))
  (animation-frame-time (svref (frames track) (1- (length (frames track))))))

(defmethod duration ((track animation-track))
  (let ((frames (frames track)))
    (- (animation-frame-time (svref (frames track) (1- (length frames))))
       (animation-frame-time (svref (frames track) 0)))))

(defmethod sequences:adjust-sequence ((track animation-track) length &rest args)
  (setf (frames track) (apply #'adjust-array (frames track) length args))
  track)

(defmethod sequences:length ((track animation-track))
  (length (frames track)))

(defmethod sequences:elt ((track animation-track) index)
  (svref (frames track) index))

(defmethod (setf sequences:elt) (value (track animation-track) index)
  (setf (svref (frames track) index) value))

(defmethod find-frame-idx ((track animation-track) x loop-p)
  (let ((x (fit-to-track track x loop-p))
        (frames (frames track)))
    (loop for i from 0 below (length frames)
          do (when (<= x (animation-frame-time (svref frames i)))
               (return (1- i)))
          finally (return (1- (length frames))))))

(defmethod sample (target (track animation-track) time &key loop-p)
  (declare (optimize speed))
  (let ((frames (frames track))
        (i (find-frame-idx track time loop-p)))
    (declare (type (signed-byte 31) i))
    (declare (type single-float time))
    (if (< i 0)
        (funcall (animation-frame-curve (svref frames 0)) target 0.0)
        (let* ((l (svref frames i))
               (r (svref frames (1+ i)))
               (x (/ (- time (animation-frame-time l))
                     (- (animation-frame-time r) (animation-frame-time l)))))
          (funcall (animation-frame-curve l) target x)))))

(defmethod differentiate ((track animation-track))
  (let ((result (make-instance 'animation-track :name (name track)))
        (frames (frames track)))
    (when (< 0 (length frames))
      (ecase (interpolation track)
        (:constant
         (setf (interpolation result) :constant)
         (setf (frames result) (vector (make-frame (start-time track) (constant 0.0))
                                       (make-frame (end-time track) (constant 0.0)))))
        (:linear
         (setf (interpolation result) :constant)
         (let ((new-frames (make-array (length frames)))
               (type (value-type track)))
           (setf (value-type result) type)
           (loop for i from 0 below (length frames)
                 for frame = (aref frames i)
                 for diff = (ecase type
                              ((real single-float) (- (sample NIL frame 1.0) (sample NIL frame 0.0)))
                              (vec2 (v- (sample (vec2) frame 1.0) (sample (vec2) frame 0.0)))
                              (vec3 (v- (sample (vec3) frame 1.0) (sample (vec3) frame 0.0)))
                              (vec4 (v- (sample (vec4) frame 1.0) (sample (vec4) frame 0.0)))
                              ;; FIXME: I think this should turn into a rotation vec3...
                              (quat (q- (sample (quat) frame 1.0) (sample (quat) frame 0.0))))
                 do (setf (aref new-frames i) (make-frame (clock frame) (constant diff))))
           (setf (frames result) new-frames)))
        (:hermite
         (implement!))
        (:bezier
         (implement!))))
    result))

(defclass fast-animation-track (animation-track)
  ((sampled-frames :initform (make-array 0 :element-type '(unsigned-byte 32)) :accessor sampled-frames)
   (sample-rate :initform 60.0 :initarg :sample-rate :accessor sample-rate)
   (find-fun :accessor find-fun)
   (duration :initform 0f0 :accessor duration)))

(defmethod update-instance-for-different-class :after ((current animation-track) (new fast-animation-track) &key)
  (setf (sampled-frames new) (generate-index-lookup-table new)))

(defun generate-index-lookup-table (track)
  (declare (optimize speed))
  (let* ((frames (frames track))
         (frame-count (length frames)))
    (declare (type simple-vector frames))
    (when (< 1 frame-count)
      (let* ((rate (sample-rate track))
             (duration (- (animation-frame-time (svref frames (1- frame-count)))
                          (animation-frame-time (svref frames 0))))
             (samples (truncate (+ rate (* rate duration))))
             (sampled (make-array samples :element-type '(unsigned-byte 32)))
             (dt (/ duration (float (1- samples) 0f0)))
             (time (start-time track)))
        (declare (type single-float rate duration dt time))
        (setf (duration track) duration)
        (dotimes (i samples sampled)
          (let ((frame-index 0))
            (loop for j downfrom (1- frame-count) to 0
                  for frame = (svref frames j)
                  do (when (<= (animation-frame-time frame) time)
                       (setf frame-index j)
                       (when (<= (- frame-count 2) frame-index)
                         (setf frame-index (- frame-count 2)))
                       (return)))
            (setf (aref sampled i) frame-index))
          (incf time dt))))))

(defmethod (setf sequences:elt) :after (value (track fast-animation-track) index)
  (setf (sampled-frames track) (generate-index-lookup-table track)))

(defmethod (setf frames) :after (value (track fast-animation-track))
  (setf (sampled-frames track) (generate-index-lookup-table track)))

(defmethod (setf sampled-frames) :after (frames (track fast-animation-track))
  (when frames
    (setf (find-fun track) (find-frame-idx-fun track))))

(defmethod find-frame-idx ((track fast-animation-track) time loop-p)
  (declare (optimize speed (safety 0)))
  (funcall (the function (find-fun track)) time loop-p))

(defmethod find-frame-idx-fun ((track fast-animation-track))
  (let* ((frames (frames track))
         (size (length frames))
         (sampled (sampled-frames track))
         (sampled-count (length sampled))
         (rate (sample-rate track))
         (duration (duration track))
         (samples (truncate (+ rate (* duration rate)))))
    (declare (simple-array frames))
    (declare (type single-float rate duration))
    (declare (type (simple-array (unsigned-byte 32) (*)) sampled))
    (declare (type (unsigned-byte 32) samples))
    (if (< 1 size)
        (lambda (time loop-p)
          (declare (optimize speed (safety 0)))
          (declare (type single-float time))
          (flet ((fit-to-track ()
                   ;; Inline here to avoid calling FRAMES.
                   (if (<= (length frames) 1)
                       0.0
                       (let ((start (animation-frame-time (svref frames 0)))
                             (end (animation-frame-time (svref frames (1- (length frames))))))
                         (if loop-p
                             (+ start (mod (- time start) (- end start)))
                             (clamp start time end))))))
            (let* ((time1 time)
                   (time (/ (the single-float (fit-to-track)) duration))
                   (index (truncate (* time (1- samples)))))
              (declare (type (unsigned-byte 32) index))
              (if (< index sampled-count)
                  (loop with l = (1- size)
                        for r from (aref sampled index)
                        while (and (< r l)
                                   (< (animation-frame-time (svref frames (1+ r)))
                                      time1))
                        do (incf index)
                        finally (return r))
                  (aref sampled (1- sampled-count))))))
        (lambda (time loop-p)
          (declare (ignore time loop-p))
          -1))))

(defmethod differentiate ((track fast-animation-track))
  (change-class (call-next-method) 'fast-animation-track))

(defclass transform-track ()
  ((name :initarg :name :initform NIL :accessor name)
   (location :initarg :location :initform (make-instance 'fast-animation-track) :accessor location)
   (scaling :initarg :scaling :initform (make-instance 'fast-animation-track) :accessor scaling)
   (rotation :initarg :rotation :initform (make-instance 'fast-animation-track) :accessor rotation)))

(defmethod print-object ((track transform-track) stream)
  (print-unreadable-object (track stream :type T)
    (if (valid-p track)
        (format stream "~s ~a ~a" (name track)
                (start-time track)
                (end-time track))
        (format stream "~s INVALID" (name track)))))

(defmethod start-time ((track transform-track))
  (let ((min most-positive-single-float))
    (flet ((try (track)
             (when (valid-p track)
               (setf min (min min (start-time track))))))
      (try (location track))
      (try (scaling track))
      (try (rotation track))
      (if (= min most-positive-single-float)
          0.0 min))))

(defmethod end-time ((track transform-track))
  (let ((max most-negative-single-float))
    (flet ((try (track)
             (when (valid-p track)
               (setf max (max max (end-time track))))))
      (try (location track))
      (try (scaling track))
      (try (rotation track))
      (if (= max most-negative-single-float)
          0.0 max))))

(defmethod sample ((transform transform) (track transform-track) time &key loop-p)
  (declare (type single-float time))
  (declare (optimize speed))
  (when (< 1 (length (location track)))
    (sample (tlocation transform) (location track) time :loop-p loop-p))
  (when (< 1 (length (scaling track)))
    (sample (tscaling transform) (scaling track) time :loop-p loop-p))
  (when (< 1 (length (rotation track)))
    (sample (trotation transform) (rotation track) time :loop-p loop-p))
  transform)

(defmethod valid-p ((track transform-track))
  (or (< 1 (length (location track)))
      (< 1 (length (scaling track)))
      (< 1 (length (rotation track)))))

(defmethod differentiate ((track transform-track))
  (make-instance 'transform-track
                 :name (name track)
                 :location (differentiate (location track))
                 :scaling (differentiate (scaling track))
                 :rotation (differentiate (rotation track))))

(defclass dummy-track (transform-track)
  ())

(defmethod sample ((transform transform) (track dummy-track) time &key loop-p)
  (declare (ignore track time loop-p))
  (v<- (tlocation transform) 0)
  (v<- (tscaling transform) 1)
  (qsetf (trotation transform) 0 0 0 1)
  transform)
