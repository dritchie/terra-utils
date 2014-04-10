
-- I got tired of repeatedly hard-coding color values, so I made this

-- dequantize
local function dq(x) return x/255.0 end 
local function dqv(v)
	local t = {}
	for _,x in ipairs(v) do
		table.insert(t, dq(x))
	end
	return t
end

local Tableau10 = 
{
	Blue = dqv({31, 119, 180}),
	Orange = dqv({255, 127, 14}),
	Green = dqv({44, 160, 44}),
	Red = dqv({214, 39, 40}),
	Purple = dqv({148, 103, 189}),
	Brown = dqv({140, 86, 75}),
	Pink = dqv({227, 119, 194}),
	Gray = dqv({127, 127, 127}),
	Yellow = dqv({188, 189, 34}),
	Teal = dqv({23, 190, 207})
}


-- Add more palettes?


return
{
	Black = dqv({0, 0, 0}),
	White = dqv({255, 255, 255}),
	Tableau10 = Tableau10
}