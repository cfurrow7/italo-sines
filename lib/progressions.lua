-- progressions.lua: Pop/italo chord progression library

local Progressions = {}

Progressions.LIST = {
  { name = "i-VII-VI-V",     steps = {1, 7, 6, 5},     tag = "italo classic" },
  { name = "I-V-vi-IV",      steps = {1, 5, 6, 4},     tag = "pop anthem" },
  { name = "vi-IV-I-V",      steps = {6, 4, 1, 5},     tag = "emotional" },
  { name = "I-vi-IV-V",      steps = {1, 6, 4, 5},     tag = "50s / stand by me" },
  { name = "i-iv-VII-i",     steps = {1, 4, 7, 1},     tag = "dark italo" },
  { name = "I-IV-vi-V",      steps = {1, 4, 6, 5},     tag = "ballad" },
  { name = "i-VI-III-VII",   steps = {1, 6, 3, 7},     tag = "depeche mode" },
  { name = "I-iii-vi-IV",    steps = {1, 3, 6, 4},     tag = "dreamy" },
  { name = "ii-V-I-IV",      steps = {2, 5, 1, 4},     tag = "jazzy disco" },
  { name = "I-V-IV-V",       steps = {1, 5, 4, 5},     tag = "rock disco" },
  { name = "I-IV",           steps = {1, 4},            tag = "two chord" },
  { name = "I-V-vi-iii-IV",  steps = {1, 5, 6, 3, 4},  tag = "canon" },
  { name = "VI-VII-i",       steps = {6, 7, 1},         tag = "epic minor" },
  { name = "I-vi-ii-V",      steps = {1, 6, 2, 5},     tag = "rhythm changes" },
  { name = "i-i-iv-V",       steps = {1, 1, 4, 5},     tag = "minor drama" },
  { name = "IV-V-iii-vi",    steps = {4, 5, 3, 6},     tag = "royal road" },
}

function Progressions.get(idx)
  return Progressions.LIST[idx] or Progressions.LIST[1]
end

function Progressions.count()
  return #Progressions.LIST
end

return Progressions
