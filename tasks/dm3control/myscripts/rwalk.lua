-- sleep(t) -- sec
-- go(vel, angle) -- %, +-rad 
-- stop()

print ('RW:START')
while true do
  print ('RW:RANDOM!')
  go (100, math.random()*0.5 - 1.0)
  sleep(5+5*math.random())
end
