-- micro:bit — working with a micro:bit from Compy over USB.
--
-- Nothing runs here. The tools are functions, and they are
-- loaded into the console, where you call them.
--
-- MICROBIT.hex is the firmware, built from
-- https://github.com/nagydani/microbit-lua main at 773ed3e.
-- tpbot.lua and tpbot-radio.lua are that firmware's start-up
-- script with the TPBot words, made from it again whenever
-- MICROBIT.hex changes.

print("micro:bit tools")
print("")
print("In the console, type:")
print("")
print("  require(\"tools\")")
print("")
print("MICROBIT.hex is the firmware; upload() puts it on")
print("the micro:bit. tpbot.lua adds the words for the")
print("TPBot robots, the Edu and the Classic;")
print("upload(\"tpbot.lua\") puts the firmware on with")
print("them. tpbot-radio.lua is the same for a robot")
print("driven by radio: it waits for a call at every")
print("start.")
