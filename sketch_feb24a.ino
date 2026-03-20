#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// These MUST match the UUIDs exactly from your Swift code!
#define SERVICE_UUID        "4FAFc201-1FB5-459E-8FCC-C5C9C331914B"
#define CHARACTERISTIC_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26A8"

// Define the pins where your motors (or test LEDs) will be connected
const int leftMotorPin = 25;  
const int rightMotorPin = 26; 

bool deviceConnected = false;
bool oldDeviceConnected = false;

// Variables for non-blocking timing
unsigned long leftMotorStartTime = 0;
unsigned long rightMotorStartTime = 0;
bool leftMotorActive = false;
bool rightMotorActive = false;
const unsigned long motorPulseDuration = 500; // How long the motor stays on (in milliseconds)

// 1. Callback class to handle device connection/disconnection
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("🟢 iPhone Connected!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("🔴 iPhone Disconnected!");
    }
};

// 2. Callback class to handle incoming data from the iPhone
class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      // Get the raw data payload
      String rxValue = pCharacteristic->getValue();

      // Check if we received our expected 3-byte payload
      if (rxValue.length() == 3) {
        
        // Byte 0: Direction Command
        uint8_t command = (uint8_t)rxValue[0]; 
        
        // Bytes 1 & 2: Distance
        uint16_t distance = ((uint8_t)rxValue[1] << 8) | (uint8_t)rxValue[2];

        // --- NEW: Format the output as (direction, distance m) ---
        String directionString = "unknown";
        if (command == 1) {
            directionString = "left";
        } else if (command == 2) {
            directionString = "right";
        } else if (command == 0) {
            directionString = "straight/arrived";
        }

        Serial.print("(");
        Serial.print(directionString);
        Serial.print(", ");
        Serial.print(distance);
        Serial.println(" m)");
        // ---------------------------------------------------------
        
        // Execute your motor/haptic logic based on the command
        if (command == 1) {
          digitalWrite(leftMotorPin, HIGH);
          leftMotorActive = true;
          leftMotorStartTime = millis(); // Start the stopwatch
          
        } else if (command == 2) {
          digitalWrite(rightMotorPin, HIGH);
          rightMotorActive = true;
          rightMotorStartTime = millis(); // Start the stopwatch
          
        }
      } else {
         Serial.println("⚠️ Received unexpected payload size.");
      }
    }
};

void setup() {
  Serial.begin(115200);
  
  // Set the motor pins as outputs and ensure they are OFF by default
  pinMode(leftMotorPin, OUTPUT);
  pinMode(rightMotorPin, OUTPUT);
  digitalWrite(leftMotorPin, LOW);
  digitalWrite(rightMotorPin, LOW);

  Serial.println("Starting BLE Server...");

  // Initialize the BLE device with a name (this is what shows up in scanners)
  BLEDevice::init("Bike_Nav_ESP32");

  // Create the BLE Server
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create the BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create the BLE Characteristic for writing data
  BLECharacteristic *pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );

  pCharacteristic->setCallbacks(new MyCallbacks());

  // Start the service
  pService->start();

  // Start advertising the Service UUID so the iPhone can find it
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  
  // These settings help iOS discover the device faster
  pAdvertising->setMinPreferred(0x06);  
  pAdvertising->setMinPreferred(0x12);
  
  BLEDevice::startAdvertising();
  Serial.println("📡 Advertising started. Waiting for iOS App to connect...");
}

void loop() {
  // If the device just disconnected
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); // This delay is fine because we are disconnected anyway
      BLEDevice::startAdvertising(); 
      Serial.println("📡 Restarted Advertising. Waiting to reconnect...");
      oldDeviceConnected = deviceConnected;
  }

  // If the device just connected
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
  }

  // Constantly check our stopwatches
  unsigned long currentMillis = millis();

  if (leftMotorActive && (currentMillis - leftMotorStartTime >= motorPulseDuration)) {
      digitalWrite(leftMotorPin, LOW);
      leftMotorActive = false;
  }

  if (rightMotorActive && (currentMillis - rightMotorStartTime >= motorPulseDuration)) {
      digitalWrite(rightMotorPin, LOW);
      rightMotorActive = false;
  }
  
  delay(10); // Small delay to keep the loop running smoothly
}
