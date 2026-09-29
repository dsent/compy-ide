-- Table to become compy.audio
local audio = { }

-- Add noises to the audio table
local names = {
  "beep",
  "blast",
  "boom",
  "correct",
  "gameover",
  "hyperjump",
  "jump",
  "knock",
  "lose",
  "pew",
  "ping",
  "punch",
  "rawr",
  "shot",
  "sword",
  "toggle",
  "win",
  "wow",
  "wrong",
  "chirp",
  "powerup",
  "step",
  "ubit_giggle",
  "ubit_happy",
  "ubit_hello",
  "ubit_mysterious",
  "ubit_sad",
  "ubit_slide",
  "ubit_soaring",
  "ubit_spring",
  "ubit_twinkle",
  "ubit_yawn"
}
for _,name in pairs(names) do
  local filename = "assets/sounds/"..name..".ogg"
  local source = love.audio.newSource(filename, "static")
  audio[name] = function()
    love.audio.stop(source)
    love.audio.play(source)
  end
end

-- see conf.lua
if love.system and love.system.getOS
    and love.system.getOS() == 'Android' then
  print('COMPYSTART the IDE\'s sounds are loaded')
end

return audio
