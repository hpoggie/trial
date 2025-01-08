(in-package #:org.shirakumo.fraf.trial.gltf)

(defun gltf-attribute-to-native-attribute (attribute)
  (case attribute
    (:position 'location)
    (:normal 'normal)
    (:tangent 'tangent)
    (:texcoord_0 'uv)
    (:texcoord_1 'uv-1)
    (:texcoord_2 'uv-2)
    (:texcoord_3 'uv-3)
    (:joints_0 'joints)
    (:joints_1 'joints-1)
    (:joints_2 'joints-2)
    (:joints_3 'joints-3)
    (:weights_0 'weights)
    (:weights_1 'weights-1)
    (:weights_2 'weights-2)
    (:weights_3 'weights-3)
    (:color_0 'color)
    (:color_1 'color-1)
    (:color_2 'color-2)
    (:color_3 'color-3)))

(defun load-vertex-attribute (mesh attribute accessor skin)
  (declare (optimize speed))
  (let ((data (vertex-data mesh))
        (stride (vertex-attribute-stride mesh))
        (offset (vertex-attribute-offset attribute mesh)))
    (declare (type (simple-array (single-float) (*)) data))
    (declare (type (unsigned-byte 32) offset stride))
    (declare (type (and sequences:sequence (not vector) (not list)) accessor))
    (when (< (length data) (length accessor))
      (setf data (adjust-array data (* (length accessor) stride) :element-type 'single-float))
      (setf (vertex-data mesh) data))
    (case (vertex-attribute-category attribute)
      (joints
       (let* ((joints (gltf:joints skin))
              (joint-count (length joints)))
         (declare (type simple-vector joints))
         (flet ((map-joint (joint)
                  (declare (type (unsigned-byte 32) joint))
                  (float (max 0 (cond ((< joint joint-count)
                                       (the (signed-byte 32) (gltf:idx (svref joints joint))))
                                      (T
                                       (v:warn :trial.gltf "Joint index ~d out of bounds [0,~d["
                                               joint joint-count)
                                       -1)))
                         0f0)))
           (loop for i of-type (unsigned-byte 32) from 0 below (length accessor)
                 for el of-type simple-array = (elt accessor i)
                 do (setf (aref data (+ (* i stride) offset 0)) (map-joint (aref el 0)))
                    (setf (aref data (+ (* i stride) offset 1)) (map-joint (aref el 1)))
                    (setf (aref data (+ (* i stride) offset 2)) (map-joint (aref el 2)))
                    (setf (aref data (+ (* i stride) offset 3)) (map-joint (aref el 3)))))))
      (uv
       (loop for i of-type (unsigned-byte 32) from 0 below (length accessor)
             for el of-type vec2 = (elt accessor i)
             do (setf (aref data (+ (* i stride) offset 0)) (vx2 el))
                (setf (aref data (+ (* i stride) offset 1)) (- 1.0 (vy2 el)))))
      (color
       (macrolet ((convert-from-array (size)
                    (let ((divider (float (1- (ash 1 size)) 0f0)))
                      `(loop for i of-type (unsigned-byte 32) from 0 below (length accessor)
                             for el of-type (simple-array (unsigned-byte ,size) (4)) = (elt accessor i)
                             do (setf (aref data (+ (* i stride) offset 0)) (/ (aref el 0) ,divider))
                                (setf (aref data (+ (* i stride) offset 1)) (/ (aref el 1) ,divider))
                                (setf (aref data (+ (* i stride) offset 2)) (/ (aref el 2) ,divider))
                                (setf (aref data (+ (* i stride) offset 3)) (/ (aref el 3) ,divider))))))
         (ecase (gltf:component-type accessor)
           (:uint8 (convert-from-array 8))
           (:uint16 (convert-from-array 16))
           (:uint32 (convert-from-array 32))
           (:float (loop for i of-type (unsigned-byte 32) from 0 below (length accessor)
                         for el of-type (or vec3 vec4) = (elt accessor i)
                         do (setf (aref data (+ (* i stride) offset 0)) (vx el))
                            (setf (aref data (+ (* i stride) offset 1)) (vy el))
                            (setf (aref data (+ (* i stride) offset 2)) (vz el))
                            (setf (aref data (+ (* i stride) offset 3)) (if (typep el 'vec4) (vw el) 1.0)))))))
      (T
       (ecase (vertex-attribute-size attribute)
         (1
          (loop for i of-type (unsigned-byte 32) from 0 below (length accessor)
                for el = (elt accessor i)
                do (setf (aref data (+ (* i stride) offset)) (float el 0f0))))
         (2
          (loop for i of-type (unsigned-byte 32) from 0 below (length accessor)
                for el of-type vec2 = (elt accessor i)
                do (setf (aref data (+ (* i stride) offset 0)) (vx2 el))
                   (setf (aref data (+ (* i stride) offset 1)) (vy2 el))))
         (3
          (loop for i of-type (unsigned-byte 32) from 0 below (length accessor)
                for el of-type vec3 = (elt accessor i)
                do (setf (aref data (+ (* i stride) offset 0)) (vx3 el))
                   (setf (aref data (+ (* i stride) offset 1)) (vy3 el))
                   (setf (aref data (+ (* i stride) offset 2)) (vz3 el))))
         (4
          (loop for i of-type (unsigned-byte 32) from 0 below (length accessor)
                for el of-type quat = (elt accessor i)
                do (setf (aref data (+ (* i stride) offset 0)) (qx el))
                   (setf (aref data (+ (* i stride) offset 1)) (qy el))
                   (setf (aref data (+ (* i stride) offset 2)) (qz el))
                   (setf (aref data (+ (* i stride) offset 3)) (qw el)))))))))

(defun load-mesh-attributes (mesh attribute-map &optional skin)
  (let* ((attributes (loop for attribute being the hash-keys of attribute-map
                           for native = (gltf-attribute-to-native-attribute attribute)
                           if native
                           collect native
                           else do (v:warn :trial.gltf "Ignoring mesh attribute ~s: don't know a native equivalent!" attribute))))
    (setf (vertex-attributes mesh) attributes)
    (loop for attribute being the hash-keys of attribute-map using (hash-value accessor)
          for native = (gltf-attribute-to-native-attribute attribute)
          do (when (member native attributes)
               (load-vertex-attribute mesh native accessor skin)))
    mesh))

(defun load-primitive (primitive &key name skin model model-name weights)
  (let* ((mesh (if (or skin (< 0 (length (gltf:targets primitive))))
                   (make-instance 'animated-mesh
                                  :name name
                                  :vertex-form (gltf:mode primitive)
                                  :skinned-p (not (null skin)))
                   (make-instance 'static-mesh
                                  :name name
                                  :vertex-form (gltf:mode primitive)))))
    (load-mesh-attributes mesh (gltf:attributes primitive) skin)
    (when (and model (gltf:material primitive))
      (setf (material mesh) (find-material (gltf-name (gltf:material primitive)) model)))
    (when (gltf:indices primitive)
      (let* ((accessor (gltf:indices primitive))
             (indexes (make-array (length accessor) :element-type (ecase (gltf:component-type accessor)
                                                                    (:uint8  '(unsigned-byte 8))
                                                                    (:uint16 '(unsigned-byte 16))
                                                                    (:uint32 '(unsigned-byte 32))))))
        (org.shirakumo.memory-regions:replace indexes accessor)
        (setf (faces mesh) (coerce indexes '(simple-array (unsigned-byte 32) 1)))))
    (when (< 0 (length (gltf:targets primitive)))
      (setf (trial::morphs mesh) (map 'vector (lambda (spec) (load-mesh-attributes (make-instance 'mesh-data) spec))
                                      (gltf:targets primitive)))
      (setf (trial::model-name mesh) model-name)
      (setf (trial::initial-weights mesh) (or weights #())))
    mesh))

(defun load-mesh (mesh model &key skin model-name)
  (let ((base-name (gltf-name mesh))
        (primitives (gltf:primitives mesh)))
    (flet ((load-primitive (primitive name)
             (load-primitive primitive :skin skin :name name :model model :weights (gltf:weights mesh) :model-name model-name)))
      (case (length primitives)
        (0 ())
        (1 (list (load-primitive (aref primitives 0) base-name)))
        (T (loop for i from 0 below (length primitives)
                 for primitive = (aref primitives i)
                 collect (load-primitive primitive (cons base-name i))))))))

(defun load-meshes (gltf model)
  (let ((meshes (make-array 0 :adjustable T :fill-pointer T)))
    (loop for node across (gltf:nodes gltf)
          for skin = (gltf:skin node)
          do (when (gltf:mesh node)
               (loop for mesh in (load-mesh (gltf:mesh node) model :skin skin :model-name (gltf-name node))
                     do (vector-push-extend mesh meshes))))
    meshes))
