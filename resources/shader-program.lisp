#|
 This file is a part of trial
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.trial)

(define-global +current-shader-program+ NIL)

(defclass shader-program (gl-resource)
  ((uniform-map :initform (make-hash-table :test 'equal) :accessor uniform-map)
   (binding-point-allocation-pointer :initform 0 :accessor binding-point-allocation-pointer)
   (shaders :initarg :shaders :initform (arg! :shaders) :accessor shaders)
   (buffers :initarg :buffers :initform () :accessor buffers)))

(defmethod describe-object ((program shader-program) stream)
  (call-next-method)
  (format stream "~&~%Buffers:~{~%  ~a~}~%~%Shaders:~%"
          (or (buffers program) (list "None")))
  (dolist (shader (shaders program))
    (format stream "~&  ~s~%" (shader-type shader))
    (format-with-line-numbers (shader-source shader) stream)))

(defun check-shader-compatibility (shaders)
  (loop with table = (make-hash-table :test 'eql)
        for shader in shaders
        do (if (gethash (shader-type shader) table)
               (error "Cannot compile two shaders of the same type into a single program~%  ~a~%  ~a"
                      (gethash (shader-type shader) table) shader)
               (setf (gethash (shader-type shader) table) shader))
           (check-allocated shader)
        finally (return shaders)))

(defmethod dependencies ((program shader-program))
  (append (call-next-method)
          (shaders program)
          (buffers program)))

(defun link-program (program shaders &optional (program-id (data-pointer program)))
  (dolist (shader shaders)
    (etypecase shader
      (integer (gl:attach-shader program-id shader))
      (shader (gl:attach-shader program-id (gl-name shader)))))
  (gl:link-program program-id)
  (dolist (shader shaders)
    (gl:detach-shader program-id (gl-name shader)))
  (unless (gl:get-program program-id :link-status)
    (error "Failed to link ~a: ~%~a"
           program (gl:get-program-info-log program-id)))
  (v:debug :trial.asset "Linked ~a with ~a." program shaders)
  (setf (data-pointer program) program-id)
  (clrhash (uniform-map program))
  (loop for buffer in (buffers program)
        do (bind buffer program)))

(defmethod (setf shaders) :before ((shaders cons) (program shader-program))
  (when (allocated-p program)
    ;; If we're already hot, relink immediately.
    (handler-bind ((resource-not-allocated (constantly-restart 'continue)))
      (check-shader-compatibility shaders)
      (link-program program shaders))))

(defmethod (setf shaders) ((other shader-program) (program shader-program))
  (setf (shaders program) (shaders other)))

(defmethod (setf buffers) :before (buffers (program shader-program))
  (when (allocated-p program)
    (loop for buffer in buffers
          do (bind buffer program))))

(defmethod allocate ((program shader-program))
  (let ((shaders (shaders program)))
    (check-shader-compatibility shaders)
    (let ((program-id (gl:create-program)))
      (with-cleanup-on-failure (gl:delete-program program-id)
        (link-program program shaders program-id)))))

(defmethod deallocate ((program shader-program))
  (clrhash (uniform-map program))
  (gl:delete-program (gl-name program)))

(declaim (inline %set-dquat))
(defun %set-quat2 (dquat dat i)
  (let ((qreal (q2real dquat))
        (qdual (q2dual dquat)))
    (setf (cffi:mem-aref dat :float (+ i 0)) (qx qreal))
    (setf (cffi:mem-aref dat :float (+ i 1)) (qy qreal))
    (setf (cffi:mem-aref dat :float (+ i 2)) (qz qreal))
    (setf (cffi:mem-aref dat :float (+ i 3)) (qw qreal))
    (setf (cffi:mem-aref dat :float (+ i 4)) (qx qdual))
    (setf (cffi:mem-aref dat :float (+ i 5)) (qy qdual))
    (setf (cffi:mem-aref dat :float (+ i 6)) (qz qdual))
    (setf (cffi:mem-aref dat :float (+ i 7)) (qw qdual))))

(declaim (inline %set-uniform))
(defun %set-uniform (location data)
  (declare (optimize speed))
  (declare (type (signed-byte 32) location))
  #+sbcl (declare (sb-ext:muffle-conditions sb-ext:compiler-note))
  ;; FIXME: this kinda blows, man.
  (macrolet ((call-array (set marr &rest args)
               #+sbcl
               `(let ((data (,marr data)))
                 (sb-sys:with-pinned-objects (data)
                   (,(find-symbol (string set) '#:%GL) location 1 ,@args (sb-sys:vector-sap data))))
               #-sbcl
               `(,(find-symbol (string set) '#:GL) location (,marr data))))
    (etypecase data
      (vec4 (call-array %gl:uniform-4fv varr4))
      (vec3 (call-array %gl:uniform-3fv varr3))
      (vec2 (call-array %gl:uniform-2fv varr2))
      (dvec4 (call-array %gl:uniform-4dv dvarr4))
      (dvec3 (call-array %gl:uniform-3dv dvarr3))
      (dvec2 (call-array %gl:uniform-2dv dvarr2))
      (ivec4 (call-array %gl:uniform-4iv ivarr4))
      (ivec3 (call-array %gl:uniform-3iv ivarr3))
      (ivec2 (call-array %gl:uniform-2iv ivarr2))
      (mat4 (call-array %gl:uniform-matrix-4fv marr4 T))
      (mat3 (call-array %gl:uniform-matrix-3fv marr3 T))
      (mat2 (call-array %gl:uniform-matrix-2fv marr2 T))
      (dmat4 (call-array %gl:uniform-matrix-4dv dmarr4 T))
      (dmat3 (call-array %gl:uniform-matrix-3dv dmarr3 T))
      (dmat2 (call-array %gl:uniform-matrix-2dv dmarr2 T))
      (quat (%gl:uniform-4f location (qx data) (qy data) (qz data) (qw data)))
      (dquat (%gl:uniform-4d location (qx data) (qy data) (qz data) (qw data)))
      (quat2 (cffi:with-foreign-object (dat :float 8)
               (%set-quat2 data dat 0)
               (%gl:uniform-matrix-2x4-fv location 1 NIL dat)))
      (single-float (%gl:uniform-1f location data))
      (double-float (%gl:uniform-1d location data))
      (fixnum (%gl:uniform-1i location data))
      (matn (ecase (mrows data)
              (2 (ecase (mcols data)
                   (3 (call-array %gl:uniform-matrix-2x3-fv marrn T))
                   (4 (call-array %gl:uniform-matrix-2x4-fv marrn T))))
              (3 (ecase (mcols data)
                   (2 (call-array %gl:uniform-matrix-3x2-fv marrn T))
                   (4 (call-array %gl:uniform-matrix-3x4-fv marrn T))))
              (4 (ecase (mcols data)
                   (2 (call-array %gl:uniform-matrix-4x2-fv marrn T))
                   (3 (call-array %gl:uniform-matrix-4x3-fv marrn T))))))
      (simple-vector
       (etypecase (svref data 0)
         (mat4 (cffi:with-foreign-object (dat :float (* 16 (length data)))
                 (loop for i from 0 below (length data)
                       do (static-vectors:replace-foreign-memory
                           (cffi:inc-pointer dat (* 16 4 i))
                           (sb-sys:vector-sap (marr4 (svref data i)))
                           (* 16 4)))
                 (%gl:uniform-matrix-4fv location (length data) T dat)))
         (mat3 (cffi:with-foreign-object (dat :float (* 9 (length data)))
                 (loop for i from 0 below (length data)
                       do (static-vectors:replace-foreign-memory
                           (cffi:inc-pointer dat (* 9 4 i))
                           (sb-sys:vector-sap (marr3 (svref data i)))
                           (* 9 4)))
                 (%gl:uniform-matrix-4fv location (length data) T dat)))
         (quat2 (cffi:with-foreign-object (dat :float (* 8 (length data)))
                  (loop for i from 0 below (length data)
                        do (%set-quat2 (aref data i) dat (* 8 i)))
                  (%gl:uniform-matrix-2x4-fv location (length data) NIL dat))))))))

(declaim (inline uniform-location))
(defun uniform-location (program name)
  (or (gethash name (uniform-map program))
      (setf (gethash name (uniform-map program))
            (gl:get-uniform-location (gl-name program) name))))

(defun (setf uniform) (data asset name)
  (declare (optimize speed))
  (let* ((name (etypecase name
                 (string name)
                 (symbol (symbol->c-name name))))
         (location (uniform-location asset name)))
    (%set-uniform location data)))

(define-compiler-macro (setf uniform) (&environment env data asset name)
  (let ((nameg (gensym "NAME"))
        (assetg (gensym "ASSET"))
        (locationg (gensym "LOCATION")))
    (cond ((constantp name env)
           `(let ((,nameg (load-time-value
                           (locally #+sbcl (declare (sb-ext:muffle-conditions sb-ext:compiler-note))
                             (etypecase ,name
                               (string ,name)
                               (symbol (symbol->c-name ,name))))))
                  (,assetg ,asset))
              (%set-uniform (uniform-location ,assetg ,nameg) ,data)))
          (T
           `(let* ((,nameg (etypecase ,name
                             (string ,name)
                             (symbol (symbol->c-name ,name))))
                   (,locationg (uniform-location ,asset ,nameg)))
              (%set-uniform ,locationg ,data))))))

(defmethod uniforms ((program shader-program))
  (let ((count (gl:get-program (gl-name program) :active-uniforms)))
    (loop for i from 0 below count
          collect (multiple-value-bind (size type name) (gl:get-active-uniform (gl-name program) i)
                    (list :index i
                          :size size
                          :type type
                          :name name
                          :location (uniform-location program name))))))

(defmethod activate ((program shader-program))
  (unless (eq +current-shader-program+ program)
    (setf +current-shader-program+ program)
    (gl:use-program (gl-name program))))
