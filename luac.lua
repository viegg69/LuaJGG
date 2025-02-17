local luac = {};
luac.lua_assert = function(test)
		if not test then
			error("assertion failed!");
		end;
	end;
function luac.make_getS(self, buff)
	local b = buff;
	return function()
		if not b then
			return nil;
		end;
		local data = b;
		b = nil;
		return data;
	end;
end;
function luac.make_getF(self, source)
	local LUAL_BUFFERSIZE = 512;
	local pos = 1;
	return function()
		local buff = source:sub(pos, (pos + LUAL_BUFFERSIZE) - 1);
		pos = math.min(#source + 1, pos + LUAL_BUFFERSIZE);
		return buff;
	end;
end;
function luac.init(self, reader, data)
	if not reader then
		return;
	end;
	local z = {};
	z.reader = reader;
	z.data = data or "";
	z.name = name;
	if not data or data == "" then
		z.n = 0;
	else
		z.n = #data;
	end;
	z.p = 0;
	return z;
end;
function luac.fill(self, z)
	local buff = z.reader();
	z.data = buff;
	if not buff or buff == "" then
		return "EOZ";
	end;
	z.n, z.p = #buff - 1, 1;
	return string.sub(buff, 1, 1);
end;
function luac.zgetc(self, z)
	local n, p = z.n, z.p + 1;
	if n > 0 then
		z.n, z.p = n - 1, p;
		return string.sub(z.data, p, p);
	else
		return self:fill(z);
	end;
end;
return luac;