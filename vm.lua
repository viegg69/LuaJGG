local opcodes = require("opcodes");
local tostring, unpack = tostring, unpack or table.unpack;
local pack = table.pack or function(...)
		return { n = select("#", ...), ... };
	end;
local OpCode = opcodes.OpCode;
local vm = {};
local function debug(...)
	if vm.debug then
		print(...);
	end;
end;
local function attemptCall(v)
	if vm.typechecking then
		local t = type(v);
		if not (t == "function" or t == "table" and (getmetatable(v) and type((getmetatable(v)).__call) == "function")) then
			error("attempt to call a " .. (t .. " value"));
		end;
	end;
	return v;
end;
local function attemptMetatable(v, n, typ, meta)
	if vm.typechecking then
		local t = type(v);
		if not (t == typ or t == "table" and (getmetatable(v) and type((getmetatable(v))[meta]) == "function")) then
			error("attempt to " .. (n .. (" a " .. (t .. " value"))));
		end;
	end;
	return v;
end;
local function attempt(v, to, ...)
	if vm.typechecking then
		local t = type(v);
		for i = 1, select("#", ...), 1 do
			if t == select(i, ...) then
				return v;
			end;
		end;
		error("attempt to " .. (to .. (" a " .. (t .. " value"))));
	end;
	return v;
end;
function vm.run(chunk, args, upvals, globals, hook)
	local R = {};
	local top = 0;
	local pc = 0;
	local code = chunk.code;
	local constants = chunk.k;
	args = args or {};
	globals = globals or _G;
	upvals = upvals or { [0] = globals };
	local openUpvalues = {};
	for i = 1, chunk.numparams, 1 do
		R[i - 1] = args[i];
		top = i - 1;
	end;
	local function RK(n)
		if n >= 256 then
			return constants[n - 256].value;
		else
			return R[n];
		end;
	end;
	local ret = pack(pcall(function()
			while true do
				local cd = code[pc];
				cd.Bx = (cd.Bx and cd.Bx > 65535) and opcodes:GETARG_sBx(cd) or cd.Bx;
				local o, a, b, c = cd.OP, cd.A, cd.Bx or cd.B, cd.C;
				if vm.debug then
					debug(pc, opcodes.opnames[o], a, b, c);
				end;
				pc = pc + 1;
				if hook then
					hook(o, a, b, c, pc - 1, opcodes.opnames[o]);
				end;
				if o == OpCode.OP_MOVE then
					R[a] = R[b];
				elseif o == OpCode.OP_LOADNIL then
					for i = a, a + b, 1 do
						R[i] = nil;
					end;
				elseif o == OpCode.OP_LOADK then
					R[a] = constants[b] and constants[b].value;
				elseif o == OpCode.OP_LOADBOOL then
					R[a] = b ~= 0;
					if c ~= 0 then
						pc = pc + 1;
					end;
				elseif o == OpCode.OP_GETTABUP then
					R[a] = (attempt(upvals[b], "index", "table", "string"))[RK(c)];
				elseif o == OpCode.OP_SETTABUP then
					(attempt(upvals[a], "index", "table", "string"))[RK(b)] = RK(c);
				elseif o == OpCode.OP_GETUPVAL then
					R[a] = upvals[b];
				elseif o == OpCode.OP_SETUPVAL then
					upvals[b] = R[a];
				elseif o == OpCode.OP_GETTABLE then
					R[a] = R[b][RK(c)];
				elseif o == OpCode.OP_SETTABLE then
					R[a][RK(b)] = RK(c);
				elseif o == OpCode.OP_ADD then
					R[a] = RK(b) + RK(c);
				elseif o == OpCode.OP_SUB then
					R[a] = RK(b) - RK(c);
				elseif o == OpCode.OP_MUL then
					R[a] = RK(b) * RK(c);
				elseif o == OpCode.OP_DIV then
					R[a] = RK(b) / RK(c);
				elseif o == OpCode.OP_MOD then
					R[a] = RK(b) % RK(c);
				elseif o == OpCode.OP_POW then
					R[a] = RK(b) ^ RK(c);
				elseif o == OpCode.OP_IDIV then
					R[a] = RK(b) // RK(c);
				elseif o == OpCode.OP_BAND then
					R[a] = RK(b) & RK(c);
				elseif o == OpCode.OP_BOR then
					R[a] = RK(b) | RK(c);
				elseif o == OpCode.OP_BXOR then
					R[a] = RK(b) ~ RK(c);
				elseif o == OpCode.OP_SHL then
					R[a] = RK(b) << RK(c);
				elseif o == OpCode.OP_SHR then
					R[a] = RK(b) >> RK(c);
				elseif o == OpCode.OP_BNOT then
					R[a] = ~R[b];
				elseif o == OpCode.OP_UNM then
					R[a] = -R[b];
				elseif o == OpCode.OP_NOT then
					R[a] = not R[b];
				elseif o == OpCode.OP_LEN then
					R[a] = #R[b];
				elseif o == OpCode.OP_CONCAT then
					local sct = {};
					for i = b, c, 1 do
						sct[#sct + 1] = tostring(R[i]);
					end;
					R[a] = table.concat(sct);
				elseif o == OpCode.OP_JMP then
					pc = pc + b;
					if a > 0 then
						for i = a - 1, chunk.maxstacksize, 1 do
							if openUpvalues[i] then
								local ouv = openUpvalues[i];
								ouv.type = 2;
								ouv.storage = R[ouv.reg];
								openUpvalues[i] = nil;
							end;
						end;
					end;
				elseif o == OpCode.OP_CALL then
					attemptCall(R[a]);
					local ret;
					if b == 1 then
						if c == 1 then
							R[a]();
						elseif c == 2 then
							R[a] = R[a]();
						else
							ret = pack(R[a]());
							if c == 0 then
								for i = 1, ret.n, 1 do
									R[(a + i) - 1] = ret[i];
								end;
								top = (a + ret.n) - 1;
							else
								local g = 1;
								for i = a, (a + c) - 1, 1 do
									R[i] = ret[g];
									g = g + 1;
								end;
							end;
						end;
					else
						local s, e;
						if b == 0 then
							s, e = a + 1, top;
						else
							s, e = a + 1, (a + b) - 1;
						end;
						if c == 1 then
							R[a](unpack(R, s, e));
						elseif c == 2 then
							R[a] = R[a](unpack(R, s, e));
						else
							ret = pack(R[a](unpack(R, s, e)));
							if c == 0 then
								for i = 1, ret.n, 1 do
									R[(a + i) - 1] = ret[i];
								end;
								top = (a + ret.n) - 1;
							else
								local g = 1;
								for i = a, (a + c) - 2, 1 do
									R[i] = ret[g];
									g = g + 1;
								end;
							end;
						end;
					end;
				elseif o == OpCode.OP_RETURN then
					local ret = {};
					local rti = 1;
					if b == 0 then
						for i = a, top, 1 do
							ret[rti] = R[i];
							rti = rti + 1;
						end;
					else
						for i = a, (a + b) - 2, 1 do
							ret[rti] = R[i];
							rti = rti + 1;
						end;
					end;
					return unpack(ret, 1, rti - 1);
				elseif o == OpCode.OP_TAILCALL then
					local cargs = {};
					local ai = 1;
					if b == 0 then
						for i = a + 1, top, 1 do
							cargs[ai] = R[i];
							ai = ai + 1;
						end;
					else
						for i = a + 1, (a + b) - 1, 1 do
							cargs[ai] = R[i];
							ai = ai + 1;
						end;
					end;
					return (attemptCall(R[a]))(unpack(cargs, 1, ai - 1));
				elseif o == OpCode.OP_VARARG then
					if b > 0 then
						local i = 1;
						for n = a, (a + b) - 1, 1 do
							R[n] = args[i];
							i = i + 1;
						end;
					else
						local base = chunk.numparams + 1;
						local nargs = #args;
						for i = base, nargs, 1 do
							R[(a + i) - base] = args[i];
						end;
						top = (a + nargs) - base;
					end;
				elseif o == OpCode.OP_SELF then
					R[a + 1] = R[b];
					R[a] = R[b][RK(c)];
				elseif o == OpCode.OP_EQ then
					if (RK(b) == RK(c)) == (a ~= 0) then
						pc = (pc + opcodes:GETARG_sBx(code[pc])) + 1;
					else
						pc = pc + 1;
					end;
				elseif o == OpCode.OP_LT then
					if (RK(b) < RK(c)) == (a ~= 0) then
						pc = (pc + opcodes:GETARG_sBx(code[pc])) + 1;
					else
						pc = pc + 1;
					end;
				elseif o == OpCode.OP_LE then
					if (RK(b) <= RK(c)) == (a ~= 0) then
						pc = (pc + opcodes:GETARG_sBx(code[pc])) + 1;
					else
						pc = pc + 1;
					end;
				elseif o == OpCode.OP_TEST then
					if not R[a] ~= (c ~= 0) then
						pc = (pc + opcodes:GETARG_sBx(code[pc])) + 1;
					else
						pc = pc + 1;
					end;
				elseif o == OpCode.OP_TESTSET then
					if not R[b] ~= (c ~= 0) then
						R[a] = R[b];
						pc = (pc + opcodes:GETARG_sBx(code[pc])) + 1;
					else
						pc = pc + 1;
					end;
				elseif o == OpCode.OP_FORPREP then
					R[a] = R[a] - R[a + 2];
					pc = pc + b;
				elseif o == OpCode.OP_FORLOOP then
					local step = R[a + 2];
					R[a] = R[a] + step;
					local idx = R[a];
					local limit = R[a + 1];
					local can;
					if step < 0 then
						can = limit <= idx;
					else
						can = limit >= idx;
					end;
					if can then
						pc = pc + b;
						R[a + 3] = R[a];
					end;
				elseif o == OpCode.OP_TFORCALL then
					local ret = { R[a](R[a + 1], R[a + 2]) };
					local i = 1;
					for n = a + 3, (a + 2) + c, 1 do
						R[n] = ret[i];
						i = i + 1;
					end;
					local cd = code[pc];
					cd.Bx = (cd.Bx and cd.Bx > 65535) and opcodes:GETARG_sBx(cd) or cd.Bx;
					o, a, b = cd.OP, cd.A, cd.Bx or cd.B;
					pc = pc + 1;
					if R[a + 1] ~= nil then
						R[a] = R[a + 1];
						pc = pc + b;
					end;
				elseif o == OpCode.OP_TFORLOOP then
					if R[a + 1] ~= nil then
						R[a] = R[a + 1];
						pc = pc + b;
					end;
				elseif o == OpCode.OP_NEWTABLE then
					R[a] = {};
				elseif o == OpCode.OP_SETLIST then
					if b > 0 then
						for i = 1, b, 1 do
							R[a][(c - 1) * 50 + i] = R[a + i];
						end;
					else
						for i = 1, top - a, 1 do
							R[a][(c - 1) * 50 + i] = R[a + i];
						end;
					end;
				elseif o == OpCode.OP_CLOSURE then
					local proto = chunk.p[b];
					local upvaldef = {};
					local upvalues = setmetatable({}, { __index = function(_, i)
								if not upvaldef[i] then
									error("unknown upvalue");
								end;
								local uvd = upvaldef[i];
								if uvd.type == 0 then
									return R[uvd.reg];
								elseif uvd.type == 1 then
									return upvals[uvd.reg];
								else
									return uvd.storage;
								end;
							end, __newindex = function(_, i, v)
								if not upvaldef[i] then
									error("unknown upvalue");
								end;
								local uvd = upvaldef[i];
								if uvd.type == 0 then
									R[uvd.reg] = v;
								elseif uvd.type == 1 then
									upvals[uvd.reg] = v;
								else
									uvd.storage = v;
								end;
							end });
					R[a] = function(...)
							return vm.run(proto, { ... }, upvalues, globals, hook);
						end;
					for i = 1, proto.nups, 1 do
						local cd = code[(pc + i) - 1];
						cd.Bx = (cd.Bx and cd.Bx > 65535) and opcodes:GETARG_sBx(cd) or cd.Bx;
						local o, a, b, c = cd.OP, cd.A, cd.Bx or cd.B, cd.C;
						debug(pc + i, "PSD", opcodes.opnames[o], a, b, c);
						if o == OpCode.OP_MOVE then
							upvaldef[i - 1] = openUpvalues[b] or { type = 0, reg = b };
							openUpvalues[b] = upvaldef[i - 1];
						elseif o == OpCode.OP_GETUPVAL then
							upvaldef[i - 1] = { type = 1, reg = b };
						else
							error("unknown upvalue psuedop");
						end;
					end;
					pc = pc + proto.nups;
				else
					error("Unknown opcode!");
				end;
			end;
		end));
	for i = 0, chunk.maxstacksize, 1 do
		if openUpvalues[i] then
			local ouv = openUpvalues[i];
			ouv.type = 2;
			ouv.storage = R[ouv.reg];
			openUpvalues[i] = nil;
		end;
	end;
	if not ret[1] then
		error(tostring(ret[2]) .. ("\n" .. (tostring(chunk.source) .. (" at pc " .. (pc - 1  .. (" line " .. tostring(chunk.lineinfo[pc - 1])))))), 0);
	else
		return unpack(ret, 2, ret.n);
	end;
end;
function vm.call(self, ...)
	return vm.run(self.chunk, ...);
end;
return setmetatable({}, { __call = vm.call });