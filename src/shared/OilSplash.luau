-- OilSplash (ModuleScript, ReplicatedStorage)
-- Salpicaduras de aceite: gotas que saltan en abanico y onda circular sobre el charco.
-- 100% cosmetico y local (sin remotes): cada cliente dibuja las suyas.
-- Se usa desde CharacterAnimator (aterrizar / derribar) y OilFighterClient (impactos "fx").
-- Potencias utiles: aterrizaje 0.15-0.85 | impacto 0.3-1 | derribo = 1 con onda.

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local OilSplash = {}

local COLORS = {
	Color3.fromRGB(255, 176, 74),
	Color3.fromRGB(222, 138, 32),
	Color3.fromRGB(255, 212, 120),
}

-- Onda: disco achatado que se expande sobre el charco y se desvanece
local function ripple(pos, radius)
	local ring = Instance.new("Part")
	ring.Name = "OilRipple"
	ring.Shape = Enum.PartType.Ball
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = COLORS[2]
	ring.Transparency = 0.35
	ring.Size = Vector3.new(1.4, 0.05, 1.4)
	ring.CFrame = CFrame.new(pos.X, pos.Y + 0.06, pos.Z)
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius, 0.05, radius),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.55)
end

-- Gotas: chorros de aceite que saltan, flotan un instante y caen de vuelta al charco
local function droplets(pos, power, dir, life)
	local n = math.floor(4 + power * 9)
	for _ = 1, n do
		local ang = math.random() * math.pi * 2
		local push
		if dir and dir.Magnitude > 0.1 then
			push = dir.Unit * (0.6 + math.random() * 0.6)
		else
			push = Vector3.new(math.cos(ang), 0, math.sin(ang)) * (0.5 + math.random() * 0.8)
		end
		local v = push * (3 + power * 8)
		local vy = (3.5 + power * 7) * (0.6 + math.random() * 0.7)
		local size = (0.16 + power * 0.34) * (0.6 + math.random() * 0.8)

		local d = Instance.new("Part")
		d.Name = "OilDrop"
		d.Shape = Enum.PartType.Ball
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		d.Material = Enum.Material.Neon
		d.Color = COLORS[math.random(#COLORS)]
		d.Transparency = 0.1
		d.Size = Vector3.one * size
		d.CFrame = CFrame.new(pos)
		d.Parent = Workspace

		-- fase 1: sube | fase 2: cae de vuelta
		local mid = pos + Vector3.new(v.X, vy, v.Z) * (life * 0.45)
		TweenService:Create(d, TweenInfo.new(life * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(mid),
			Size = Vector3.one * (size * 1.4),
		}):Play()
		task.delay(life * 0.45, function()
			if not d.Parent then
				return
			end
			local land = pos + Vector3.new(v.X * life, 0, v.Z * life)
			TweenService:Create(d, TweenInfo.new(life * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(land),
				Transparency = 1,
				Size = Vector3.one * (size * 0.5),
			}):Play()
		end)
		Debris:AddItem(d, life + 0.1)
	end
end

-- pos: punto del charco (mejor en el suelo) | power: 0..1 (fuerza)
-- opts: { dir = Vector3 (abanico direccional), ripple = true (onda en el suelo) }
function OilSplash.splash(pos, power, opts)
	if not pos then
		return
	end
	power = math.clamp(power or 0.5, 0.1, 1)
	opts = opts or {}
	local life = 0.35 + power * 0.35
	droplets(pos, power, opts.dir, life)
	if opts.ripple then
		ripple(pos, 3.5 + power * 7)
	end
end

-- Aterrizaje: la velocidad de caida manda la cantidad de salpicadura
function OilSplash.land(pos, impact)
	OilSplash.splash(pos, math.clamp((impact - 6) / 26, 0.15, 0.85), { ripple = true })
end

-- Derribo: chapuzon grande con onda, empujado hacia donde vuela el cuerpo
function OilSplash.knock(pos, dir)
	OilSplash.splash(pos, 1, { ripple = true, dir = dir })
end

return OilSplash
