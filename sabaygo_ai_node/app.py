from flask import Flask, jsonify
import cv2
from ultralytics import YOLO
import base64

app = Flask(__name__)

# Load the lightweight YOLOv8 Nano model (downloads automatically the first time)
print("Loading YOLOv8 Model...")
model = YOLO('yolov8n.pt') 

@app.route('/api/audit/live', methods=['GET'])
def live_audit():
    print("\n--- [SABAYGO AI NODE] LIVE AUDIT TRIGGERED ---")
    print("Activating van cabin camera...")
    
    # 1. OpenCV turns on the webcam (0 is usually the default laptop camera)
    cap = cv2.VideoCapture(0)
    
    # Give the camera a brief moment to adjust to the room lighting
    for _ in range(5):
        cap.read()
        
    success, frame = cap.read()
    cap.release() # Immediately release the camera so it doesn't overheat your laptop

    if not success:
        print(">> ERROR: Failed to access webcam.")
        return jsonify({"error": "Failed to access webcam"}), 500

    print("Camera frame captured. Running YOLOv8 inference...")

    # 2. YOLOv8 processes the image. classes=[0] tells it to ONLY look for people.
    results = model(frame, classes=[0])
    
    # Extract the number of people detected
    person_count = len(results[0].boxes)
    print(f">> SUCCESS: YOLOv8 visual count is {person_count} passenger(s).")

    # 3. Draw the YOLO bounding boxes directly onto the image
    annotated_frame = results[0].plot()

    # 4. OpenCV converts the image into a format we can send over the network
    _, buffer = cv2.imencode('.jpg', annotated_frame)
    image_base64 = base64.b64encode(buffer).decode('utf-8')

    print("Encoding visual proof and transmitting to Operator Console...\n")

    # 5. Send the math and the visual proof back to your Flutter app
    return jsonify({
        "visual_count": person_count,
        "image_data": image_base64
    })

if __name__ == '__main__':
    # Run the server on all local IP addresses at port 5000
    print("\n[READY] SabayGo Backend Listening...")
    app.run(host='0.0.0.0', port=5000)