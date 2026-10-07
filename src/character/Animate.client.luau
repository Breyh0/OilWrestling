-- Animate (LocalScript vacio a proposito)
-- Un script con este nombre en StarterCharacterScripts reemplaza al "Animate" por defecto de Roblox,
-- que reproducia las animaciones estandar. De las poses se encarga CharacterAnimator
-- (StarterPlayerScripts), que anima a todos los luchadores de forma procedural.
-- El BindableFunction PlayEmote evita errores del menu de emotes del cliente.

local pe = Instance.new("BindableFunction")
pe.Name = "PlayEmote"
pe.OnInvoke = function()
	return false
end
pe.Parent = script
