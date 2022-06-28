import RPi.GPIO as GPIO
import time

# setup the GPIO pin for the servo
servo_pin1 = 12
servo_pin2 = 13
GPIO.setmode(GPIO.BCM)
GPIO.setup(servo_pin1,GPIO.OUT)
GPIO.setup(servo_pin2,GPIO.OUT)

# setup PWM process
pwm1 = GPIO.PWM(servo_pin1,50) # 50 Hz (20 ms PWM period)
pwm2 = GPIO.PWM(servo_pin2,50)

pwm1.start(7) # start PWM by rotating to 90 degrees
pwm2.start(7)

for ii in range(0,3):
    pwm1.ChangeDutyCycle(5.0) # rotate to 0 degrees
    pwm2.ChangeDutyCycle(5.0)
    time.sleep(0.5)
    pwm1.ChangeDutyCycle(9.0) # rotate to 180 degrees
    pwm2.ChangeDutyCycle(9.0)
    time.sleep(0.5)
    pwm1.ChangeDutyCycle(7.0) # rotate to 90 degrees
    pwm2.ChangeDutyCycle(7.0)
    time.sleep(0.5)

pwm1.ChangeDutyCycle(0) # this prevents jitter
pwm1.stop() # stops the pwm on 13
pwm2.ChangeDutyCycle(0)
pwm2.stop()
GPIO.cleanup() # good practice when finished using a pin