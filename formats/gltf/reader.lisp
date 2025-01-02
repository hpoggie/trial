(in-package #:org.shirakumo.fraf.trial.gltf)

(defun to-vec (thing)
  (let ((vec (ecase (length thing) (2 (vec2)) (3 (vec3)) (4 (vec4)))))
    (map-into (varr vec) (lambda (x) (float x 0f0)) thing)
    vec))

(defun gltf-name (thing)
  (trial:lispify-name (or (gltf:name thing) (gltf:idx thing))))

(defun gltf-node-transform (node)
  (let ((matrix (gltf:matrix node))
        (translation (gltf:translation node))
        (scale (gltf:scale node))
        (rotation (gltf:rotation node)))
    (let ((transform (if matrix
                         (tfrom-mat (mat4 matrix))
                         (transform))))
      (when translation
        (vsetf (tlocation transform)
               (aref translation 0)
               (aref translation 1)
               (aref translation 2)))
      (when scale
        (vsetf (tscaling transform)
               (aref scale 0)
               (aref scale 1)
               (aref scale 2)))
      (when rotation
        (qsetf (trotation transform)
               (aref rotation 0)
               (aref rotation 1)
               (aref rotation 2)
               (aref rotation 3)))
      transform)))

(defmethod gltf:construct-element-reader ((element-type (eql :vec2)) (component-type (eql :float)))
  (lambda (ptr)
    (values (vec (cffi:mem-ref ptr :float)
                 (cffi:mem-ref (cffi:incf-pointer ptr 4) :float))
            (cffi:incf-pointer ptr 4))))

(defmethod gltf:construct-element-reader ((element-type (eql :vec3)) (component-type (eql :float)))
  (lambda (ptr)
    (values (vec (cffi:mem-ref ptr :float)
                 (cffi:mem-ref (cffi:incf-pointer ptr 4) :float)
                 (cffi:mem-ref (cffi:incf-pointer ptr 4) :float))
            (cffi:incf-pointer ptr 4))))

(defmethod gltf:construct-element-reader ((element-type (eql :vec4)) (component-type (eql :float)))
  (lambda (ptr)
    (values (quat (cffi:mem-ref ptr :float)
                  (cffi:mem-ref (cffi:incf-pointer ptr 4) :float)
                  (cffi:mem-ref (cffi:incf-pointer ptr 4) :float)
                  (cffi:mem-ref (cffi:incf-pointer ptr 4) :float))
            (cffi:incf-pointer ptr 4))))

(defmethod gltf:construct-element-reader ((element-type (eql :mat4)) (component-type (eql :float)))
  (lambda (ptr)
    (let ((elements (make-array 16 :element-type 'single-float)))
      (dotimes (i (length elements))
        (setf (aref elements i) (cffi:mem-aref ptr :float i)))
      (values (nmtranspose (mat4 elements))
              (cffi:inc-pointer ptr (* 4 16))))))

(defmethod gltf:construct-element-reader ((element-type (eql :vec2)) (component-type (eql :double)))
  (lambda (ptr)
    (values (dvec (cffi:mem-ref ptr :double)
                  (cffi:mem-ref (cffi:incf-pointer ptr 8) :double))
            (cffi:incf-pointer ptr 8))))

(defmethod gltf:construct-element-reader ((element-type (eql :vec3)) (component-type (eql :double)))
  (lambda (ptr)
    (values (dvec (cffi:mem-ref ptr :double)
                  (cffi:mem-ref (cffi:incf-pointer ptr 8) :double)
                  (cffi:mem-ref (cffi:incf-pointer ptr 8) :double))
            (cffi:incf-pointer ptr 8))))

(defmethod gltf:construct-element-reader ((element-type (eql :vec4)) (component-type (eql :double)))
  (lambda (ptr)
    (values (dquat (cffi:mem-ref ptr :double)
                   (cffi:mem-ref (cffi:incf-pointer ptr 8) :double)
                   (cffi:mem-ref (cffi:incf-pointer ptr 8) :double)
                   (cffi:mem-ref (cffi:incf-pointer ptr 8) :double))
            (cffi:incf-pointer ptr 8))))

(defmethod gltf:construct-element-reader ((element-type (eql :mat4)) (component-type (eql :double)))
  (lambda (ptr)
    (let ((elements (make-array 16 :element-type 'double-float)))
      (dotimes (i (length elements))
        (setf (aref elements i) (cffi:mem-aref ptr :double i)))
      (values (nmtranspose (dmat4 elements))
              (cffi:inc-pointer ptr (* 8 16))))))

(defmethod gltf:construct-element-reader ((element-type (eql :vec2)) (component-type (eql :int32)))
  (lambda (ptr)
    (values (ivec (cffi:mem-ref ptr :int32)
                  (cffi:mem-ref (cffi:incf-pointer ptr 4) :int32))
            (cffi:incf-pointer ptr 4))))

(defmethod gltf:construct-element-reader ((element-type (eql :vec3)) (component-type (eql :int32)))
  (lambda (ptr)
    (values (ivec (cffi:mem-ref ptr :int32)
                  (cffi:mem-ref (cffi:incf-pointer ptr 4) :int32)
                  (cffi:mem-ref (cffi:incf-pointer ptr 4) :int32))
            (cffi:incf-pointer ptr 4))))

(defmethod gltf:construct-element-reader ((element-type (eql :vec4)) (component-type (eql :int32)))
  (lambda (ptr)
    (values (ivec (cffi:mem-ref ptr :int32)
                  (cffi:mem-ref (cffi:incf-pointer ptr 4) :int32)
                  (cffi:mem-ref (cffi:incf-pointer ptr 4) :int32)
                  (cffi:mem-ref (cffi:incf-pointer ptr 4) :int32))
            (cffi:incf-pointer ptr 4))))

(defmethod gltf:construct-element-reader ((element-type (eql :mat4)) (component-type (eql :int32)))
  (lambda (ptr)
    (let ((elements (make-array 16 :element-type '(signed-byte 32))))
      (dotimes (i (length elements))
        (setf (aref elements i) (cffi:mem-aref ptr :int32 i)))
      (values (nmtranspose (imat4 elements))
              (cffi:inc-pointer ptr (* 4 16))))))

(defmethod mem:call-with-memory-region ((function function) (accessor gltf:accessor) &key (start 0))
  (let ((region (mem:memory-region
                 (cffi:inc-pointer (gltf:start accessor) start)
                 (* (gltf:size accessor) (gltf:byte-stride accessor)))))
    (declare (dynamic-extent region))
    (funcall function region)))
