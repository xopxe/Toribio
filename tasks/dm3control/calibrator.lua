-- http://mathworld.wolfram.com/LagrangeInterpolatingPolynomial.html

return function( calibration )
  --{{0,-90}, {1, 0}, {2, 90}}
  local x1, y1 = calibration[1][1], calibration[1][2]
  local x2, y2 = calibration[2][1], calibration[2][2]
  local x3, y3 = calibration[3][1], calibration[3][2]
  
  local q1 = y1 / ((x1-x2) * (x1-x3))
  local q2 = y2 / ((x2-x1) * (x2-x3))
  local q3 = y3 / ((x3-x1) * (x3-x2))
  
  return function(x)
    --[[
    local p_x = (((x-x2)*(x-x3)) / ((x1-x2)*(x1-x3))) * y1
              + (((x-x1)*(x-x3)) / ((x2-x1)*(x2-x3))) * y2
              + (((x-x1)*(x-x2)) / ((x3-x1)*(x3-x2))) * y3
    --]]
    local x_x1, x_x2, x_x3 = x-x1, x-x2, x-x3
    local p_x = x_x2 * x_x3 * q1 + x_x1 * x_x3 * q2 + x_x1 * x_x2 * q3
    return p_x
  end
end
