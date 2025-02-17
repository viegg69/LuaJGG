local lex = require("lex");
local opcodes = require("opcodes");
local code = {};
code.MAXSTACK = 250;
code.LUA_MULTRET = -1;
code.MAX_INT = lex.MAX_INT or 2147483645;
function code.ttisnumber(self, o)
	if o then
		return type(o.value) == "number";
	else
		return false;
	end;
end;
function code.nvalue(self, o)
	return o.value;
end;
function code.setnilvalue(self, o)
	o.value = nil;
end;
function code.setsvalue(self, o, x)
	o.value = x;
end;
code.setnvalue = code.setsvalue;
code.sethvalue = code.setsvalue;
code.setbvalue = code.setsvalue;
function code.growvector(self, L, v, nelems, size, t, limit, e)
	if nelems >= limit then
		error(e);
	end;
end;
function code.numadd(self, a, b)
	return a + b;
end;
function code.numsub(self, a, b)
	return a - b;
end;
function code.nummul(self, a, b)
	return a * b;
end;
function code.numdiv(self, a, b)
	return a / b;
end;
function code.nummod(self, a, b)
	return a % b;
end;
function code.numidiv(self, a, b)
	return a // b;
end;
function code.numband(self, a, b)
	return a & b;
end;
function code.numbor(self, a, b)
	return a | b;
end;
function code.numbxor(self, a, b)
	return a ~ b;
end;
function code.numshr(self, a, b)
	return a << b;
end;
function code.numshl(self, a, b)
	return a >> b;
end;
function code.numbnot(self, a)
	return ~a;
end;
function code.numpow(self, a, b)
	return a ^ b;
end;
function code.numunm(self, a)
	return -a;
end;
function code.numisnan(self, a)
	return not a == a;
end;
code.NO_JUMP = -1;
code.BinOpr = {
		OPR_ADD = 0,
		OPR_SUB = 1,
		OPR_MUL = 2,
		OPR_DIV = 3,
		OPR_MOD = 4,
		OPR_POW = 5,
		OPR_IDIV = 6,
		OPR_BAND = 7,
		OPR_BOR = 8,
		OPR_BXOR = 9,
		OPR_SHR = 10,
		OPR_SHL = 11,
		OPR_CONCAT = 12,
		OPR_NE = 13,
		OPR_EQ = 14,
		OPR_LT = 15,
		OPR_LE = 16,
		OPR_GT = 17,
		OPR_GE = 18,
		OPR_AND = 19,
		OPR_OR = 20,
		OPR_NOBINOPR = 21,
	};
codenOpr = {
		OPR_MINUS = 0,
		OPR_NOT = 1,
		OPR_LEN = 2,
		OPR_BNOT = 3,
		OPR_NOUNOPR = 4,
	};
function code.getcode(self, fs, e)
	return fs.f.code[e.info];
end;
function code.codeAsBx(self, fs, o, A, sBx)
	return self:codeABx(fs, o, A, sBx + opcodes.MAXARG_sBx);
end;
function code.setmultret(self, fs, e)
	self:setreturns(fs, e, self.LUA_MULTRET);
end;
function code.hasjumps(self, e)
	return e.t ~= e.f;
end;
function code.isnumeral(self, e)
	return e.k == "VKNUM" and (e.t == self.NO_JUMP and e.f == self.NO_JUMP);
end;
function code._nil(self, fs, from, n)
	if fs.pc > fs.lasttarget then
		if fs.pc == 0 then
			if from >= fs.nactvar then
				return;
			end;
		else
			local previous = fs.f.code[fs.pc - 1];
			if opcodes:GET_OPCODE(previous) == "OP_LOADNIL" then
				local pfrom = opcodes:GETARG_A(previous);
				local pto = opcodes:GETARG_B(previous);
				if pfrom <= from and from <= pto + 1 then
					if (from + n) - 1 > pto then
						opcodes:SETARG_B(previous, (from + n) - 1);
					end;
					return;
				end;
			end;
		end;
	end;
	self:codeABC(fs, "OP_LOADNIL", from, n - 1, 0);
end;
function code.jump(self, fs)
	local jpc = fs.jpc;
	fs.jpc = self.NO_JUMP;
	local j = self:codeAsBx(fs, "OP_JMP", 0, self.NO_JUMP);
	j = self:concat(fs, j, jpc);
	return j;
end;
function code.ret(self, fs, first, nret)
	self:codeABC(fs, "OP_RETURN", first, nret + 1, 0);
end;
function code.condjump(self, fs, op, A, B, C)
	self:codeABC(fs, op, A, B, C);
	return self:jump(fs);
end;
function code.fixjump(self, fs, pc, dest)
	local jmp = fs.f.code[pc];
	local offset = dest - (pc + 1);
	assert(dest ~= self.NO_JUMP);
	if math.abs(offset) > opcodes.MAXARG_sBx then
		lex:syntaxerror(fs.ls, "control structure too long");
	end;
	opcodes:SETARG_sBx(jmp, offset);
end;
function code.getlabel(self, fs)
	fs.lasttarget = fs.pc;
	return fs.pc;
end;
function code.getjump(self, fs, pc)
	local offset = opcodes:GETARG_sBx(fs.f.code[pc]);
	if offset == self.NO_JUMP then
		return self.NO_JUMP;
	else
		return (pc + 1) + offset;
	end;
end;
function code.getjumpcontrol(self, fs, pc)
	local pi = fs.f.code[pc];
	local ppi = fs.f.code[pc - 1];
	if pc >= 1 and opcodes:testTMode(opcodes:GET_OPCODE(ppi)) ~= 0 then
		return ppi;
	else
		return pi;
	end;
end;
function code.need_value(self, fs, list)
	while list ~= self.NO_JUMP do
		local i = self:getjumpcontrol(fs, list);
		if opcodes:GET_OPCODE(i) ~= "OP_TESTSET" then
			return true;
		end;
		list = self:getjump(fs, list);
	end;
	return false;
end;
function code.patchtestreg(self, fs, node, reg)
	local i = self:getjumpcontrol(fs, node);
	if opcodes:GET_OPCODE(i) ~= "OP_TESTSET" then
		return false;
	end;
	if reg ~= opcodes.NO_REG and reg ~= opcodes:GETARG_B(i) then
		opcodes:SETARG_A(i, reg);
	else
		opcodes:SET_OPCODE(i, "OP_TEST");
		local b = opcodes:GETARG_B(i);
		opcodes:SETARG_A(i, b);
		opcodes:SETARG_B(i, 0);
	end;
	return true;
end;
function code.removevalues(self, fs, list)
	while list ~= self.NO_JUMP do
		self:patchtestreg(fs, list, opcodes.NO_REG);
		list = self:getjump(fs, list);
	end;
end;
function code.patchlistaux(self, fs, list, vtarget, reg, dtarget)
	while list ~= self.NO_JUMP do
		local _next = self:getjump(fs, list);
		if self:patchtestreg(fs, list, reg) then
			self:fixjump(fs, list, vtarget);
		else
			self:fixjump(fs, list, dtarget);
		end;
		list = _next;
	end;
end;
function code.dischargejpc(self, fs)
	self:patchlistaux(fs, fs.jpc, fs.pc, opcodes.NO_REG, fs.pc);
	fs.jpc = self.NO_JUMP;
end;
function code.patchlist(self, fs, list, target)
	if target == fs.pc then
		self:patchtohere(fs, list);
	else
		assert(target < fs.pc);
		self:patchlistaux(fs, list, target, opcodes.NO_REG, target);
	end;
end;
function code.patchclose(self, fs, list, level)
	local f = fs.f;
	level = level + 1;
	while list ~= self.NO_JUMP do
		local next = self:getjump(fs, list);
		assert(opcodes:GET_OPCODE(f.code[list]) == "OP_JMP" and (opcodes:GETARG_A(f.code[list]) == 0 or opcodes:GETARG_A(f.code[list]) >= level));
		opcodes:SETARG_A(f.code, list, level);
		list = next;
	end;
end;
function code.patchtohere(self, fs, list)
	self:getlabel(fs);
	fs.jpc = self:concat(fs, fs.jpc, list);
end;
function code.concat(self, fs, l1, l2)
	if l2 == self.NO_JUMP then
		return l1;
	elseif l1 == self.NO_JUMP then
		return l2;
	else
		local list = l1;
		local _next = self:getjump(fs, list);
		while _next ~= self.NO_JUMP do
			list = _next;
			_next = self:getjump(fs, list);
		end;
		self:fixjump(fs, list, l2);
	end;
	return l1;
end;
function code.checkstack(self, fs, n)
	local newstack = fs.freereg + n;
	if newstack > fs.f.maxstacksize then
		if newstack >= self.MAXSTACK then
			lex:syntaxerror(fs.ls, "function or expression too complex");
		end;
		fs.f.maxstacksize = newstack;
	end;
end;
function code.reserveregs(self, fs, n)
	self:checkstack(fs, n);
	fs.freereg = fs.freereg + n;
end;
function code.freereg(self, fs, reg)
	if not opcodes:ISK(reg) and reg >= fs.nactvar then
		fs.freereg = fs.freereg - 1;
		assert(reg == fs.freereg);
	end;
end;
function code.freeexp(self, fs, e)
	if e.k == "VNONRELOC" then
		self:freereg(fs, e.info);
	end;
end;
function code.addk(self, fs, k, v)
	local L = fs.L;
	local idx = fs.h[k.value];
	local f = fs.f;
	if self:ttisnumber(idx) then
		return self:nvalue(idx);
	else
		idx = {};
		self:setnvalue(idx, fs.nk);
		fs.h[k.value] = idx;
		self:growvector(L, f.k, fs.nk, f.sizek, nil, opcodes.MAXARG_Bx, "constant table overflow");
		f.k[fs.nk] = v;
		local nk = fs.nk;
		fs.nk = fs.nk + 1;
		return nk;
	end;
end;
function code.stringK(self, fs, s)
	local o = {};
	self:setsvalue(o, s);
	return self:addk(fs, o, o);
end;
function code.numberK(self, fs, r)
	local o = {};
	self:setnvalue(o, r);
	return self:addk(fs, o, o);
end;
function code.boolK(self, fs, b)
	local o = {};
	self:setbvalue(o, b);
	return self:addk(fs, o, o);
end;
function code.nilK(self, fs)
	local k, v = {}, {};
	self:setnilvalue(v);
	self:sethvalue(k, fs.h);
	return self:addk(fs, k, v);
end;
function code.setreturns(self, fs, e, nresults)
	if e.k == "VCALL" then
		opcodes:SETARG_C(self:getcode(fs, e), nresults + 1);
	elseif e.k == "VVARARG" then
		opcodes:SETARG_B(self:getcode(fs, e), nresults + 1);
		opcodes:SETARG_A(self:getcode(fs, e), fs.freereg);
		code:reserveregs(fs, 1);
	end;
end;
function code.setoneret(self, fs, e)
	if e.k == "VCALL" then
		e.k = "VNONRELOC";
		e.info = opcodes:GETARG_A(self:getcode(fs, e));
	elseif e.k == "VVARARG" then
		opcodes:SETARG_B(self:getcode(fs, e), 2);
		e.k = "VRELOCABLE";
	end;
end;
function code.dischargevars(self, fs, e)
	local k = e.k;
	if k == "VLOCAL" then
		e.k = "VNONRELOC";
	elseif k == "VUPVAL" then
		e.info = self:codeABC(fs, "OP_GETUPVAL", 0, e.info, 0);
		e.k = "VRELOCABLE";
	elseif k == "VINDEXED" then
		local op = "OP_GETTABUP";
		self:freereg(fs, e.aux);
		if e.ind_vt == "VLOCAL" then
			self:freereg(fs, e.info);
			op = "OP_GETTABLE";
		end;
		e.info = self:codeABC(fs, op, 0, e.info, e.aux);
		e.k = "VRELOCABLE";
	elseif k == "VVARARG" or k == "VCALL" then
		self:setoneret(fs, e);
	else
 
	end;
end;
function code.code_label(self, fs, A, b, jump)
	self:getlabel(fs);
	return self:codeABC(fs, "OP_LOADBOOL", A, b, jump);
end;
function code.discharge2reg(self, fs, e, reg)
	self:dischargevars(fs, e);
	local k = e.k;
	if k == "VNIL" then
		self:_nil(fs, reg, 1);
	elseif k == "VFALSE" or k == "VTRUE" then
		self:codeABC(fs, "OP_LOADBOOL", reg, e.k == "VTRUE" and 1 or 0, 0);
	elseif k == "VK" then
		self:codeABx(fs, "OP_LOADK", reg, e.info);
	elseif k == "VKNUM" then
		self:codeABx(fs, "OP_LOADK", reg, self:numberK(fs, e.nval));
	elseif k == "VRELOCABLE" then
		local pc = self:getcode(fs, e);
		opcodes:SETARG_A(pc, reg);
	elseif k == "VNONRELOC" then
		if reg ~= e.info then
			self:codeABC(fs, "OP_MOVE", reg, e.info, 0);
		end;
	else
		assert(e.k == "VVOID" or e.k == "VJMP");
		return;
	end;
	e.info = reg;
	e.k = "VNONRELOC";
end;
function code.discharge2anyreg(self, fs, e)
	if e.k ~= "VNONRELOC" then
		self:reserveregs(fs, 1);
		self:discharge2reg(fs, e, fs.freereg - 1);
	end;
end;
function code.exp2reg(self, fs, e, reg)
	self:discharge2reg(fs, e, reg);
	if e.k == "VJMP" then
		e.t = self:concat(fs, e.t, e.info);
	end;
	if self:hasjumps(e) then
		local final;
		local p_f = self.NO_JUMP;
		local p_t = self.NO_JUMP;
		if self:need_value(fs, e.t) or self:need_value(fs, e.f) then
			local fj = e.k == "VJMP" and self.NO_JUMP or self:jump(fs);
			p_f = self:code_label(fs, reg, 0, 1);
			p_t = self:code_label(fs, reg, 1, 0);
			self:patchtohere(fs, fj);
		end;
		final = self:getlabel(fs);
		self:patchlistaux(fs, e.f, final, reg, p_f);
		self:patchlistaux(fs, e.t, final, reg, p_t);
	end;
	e.f, e.t = self.NO_JUMP, self.NO_JUMP;
	e.info = reg;
	e.k = "VNONRELOC";
end;
function code.exp2nextreg(self, fs, e)
	self:dischargevars(fs, e);
	self:freeexp(fs, e);
	self:reserveregs(fs, 1);
	self:exp2reg(fs, e, fs.freereg - 1);
end;
function code.exp2anyreg(self, fs, e)
	self:dischargevars(fs, e);
	if e.k == "VNONRELOC" then
		if not self:hasjumps(e) then
			return e.info;
		end;
		if e.info >= fs.nactvar then
			self:exp2reg(fs, e, e.info);
			return e.info;
		end;
	end;
	self:exp2nextreg(fs, e);
	return e.info;
end;
function code.exp2anyregup(self, fs, e)
	if e.k ~= "VUPVAL" or self:hasjumps(e) then
		self:exp2anyreg(fs, e);
	end;
end;
function code.exp2val(self, fs, e)
	if self:hasjumps(e) then
		self:exp2anyreg(fs, e);
	else
		self:dischargevars(fs, e);
	end;
end;
function code.exp2RK(self, fs, e)
	self:exp2val(fs, e);
	local k = e.k;
	if k == "VKNUM" or k == "VTRUE" or k == "VFALSE" or k == "VNIL" then
		if fs.nk <= opcodes.MAXINDEXRK then
			if e.k == "VNIL" then
				e.info = self:nilK(fs);
			else
				e.info = e.k == "VKNUM" and self:numberK(fs, e.nval) or self:boolK(fs, e.k == "VTRUE");
			end;
			e.k = "VK";
			return opcodes:RKASK(e.info);
		end;
	elseif k == "VK" then
		if e.info <= opcodes.MAXINDEXRK then
			return opcodes:RKASK(e.info);
		end;
	else
 
	end;
	return self:exp2anyreg(fs, e);
end;
function code.storevar(self, fs, var, ex)
	local k = var.k;
	if k == "VLOCAL" then
		self:freeexp(fs, ex);
		self:exp2reg(fs, ex, var.info);
		return;
	elseif k == "VUPVAL" then
		local e = self:exp2anyreg(fs, ex);
		self:codeABC(fs, "OP_SETUPVAL", e, var.info, 0);
	elseif k == "VINDEXED" then
		local op = var.ind_vt == "VLOCAL" and "OP_SETTABLE" or "OP_SETTABUP";
		local e = self:exp2RK(fs, ex);
		self:codeABC(fs, op, var.info, var.aux, e);
	else
		assert(0);
	end;
	self:freeexp(fs, ex);
end;
function code._self(self, fs, e, key)
	self:exp2anyreg(fs, e);
	self:freeexp(fs, e);
	local func = fs.freereg;
	self:reserveregs(fs, 2);
	self:codeABC(fs, "OP_SELF", func, e.info, self:exp2RK(fs, key));
	self:freeexp(fs, key);
	e.info = func;
	e.k = "VNONRELOC";
end;
function code.invertjump(self, fs, e)
	local pc = self:getjumpcontrol(fs, e.info);
	assert(opcodes:testTMode(opcodes:GET_OPCODE(pc)) ~= 0 and (opcodes:GET_OPCODE(pc) ~= "OP_TESTSET" and opcodes:GET_OPCODE(pc) ~= "OP_TEST"));
	opcodes:SETARG_A(pc, opcodes:GETARG_A(pc) == 0 and 1 or 0);
end;
function code.jumponcond(self, fs, e, cond)
	if e.k == "VRELOCABLE" then
		local ie = self:getcode(fs, e);
		if opcodes:GET_OPCODE(ie) == "OP_NOT" then
			fs.pc = fs.pc - 1;
			return self:condjump(fs, "OP_TEST", opcodes:GETARG_B(ie), 0, cond and 0 or 1);
		end;
	end;
	self:discharge2anyreg(fs, e);
	self:freeexp(fs, e);
	return self:condjump(fs, "OP_TESTSET", opcodes.NO_REG, e.info, cond and 1 or 0);
end;
function code.goiftrue(self, fs, e)
	local pc;
	self:dischargevars(fs, e);
	local k = e.k;
	if k == "VK" or k == "VKNUM" or k == "VTRUE" then
		pc = self.NO_JUMP;
	elseif k == "VFALSE" then
		pc = self:jump(fs);
	elseif k == "VJMP" then
		self:invertjump(fs, e);
		pc = e.info;
	else
		pc = self:jumponcond(fs, e, false);
	end;
	e.f = self:concat(fs, e.f, pc);
	self:patchtohere(fs, e.t);
	e.t = self.NO_JUMP;
end;
function code.goiffalse(self, fs, e)
	local pc;
	self:dischargevars(fs, e);
	local k = e.k;
	if k == "VNIL" or k == "VFALSE" then
		pc = self.NO_JUMP;
	elseif k == "VTRUE" then
		pc = self:jump(fs);
	elseif k == "VJMP" then
		pc = e.info;
	else
		pc = self:jumponcond(fs, e, true);
	end;
	e.t = self:concat(fs, e.t, pc);
	self:patchtohere(fs, e.f);
	e.f = self.NO_JUMP;
end;
function code.codenot(self, fs, e)
	self:dischargevars(fs, e);
	local k = e.k;
	if k == "VNIL" or k == "VFALSE" then
		e.k = "VTRUE";
	elseif k == "VK" or k == "VKNUM" or k == "VTRUE" then
		e.k = "VFALSE";
	elseif k == "VJMP" then
		self:invertjump(fs, e);
	elseif k == "VRELOCABLE" or k == "VNONRELOC" then
		self:discharge2anyreg(fs, e);
		self:freeexp(fs, e);
		e.info = self:codeABC(fs, "OP_NOT", 0, e.info, 0);
		e.k = "VRELOCABLE";
	else
		assert(0);
	end;
	e.f, e.t = e.t, e.f;
	self:removevalues(fs, e.f);
	self:removevalues(fs, e.t);
end;
function code.indexed(self, fs, t, k)
	t.aux = self:exp2RK(fs, k);
	t.ind_vt = t.k == "VUPVAL" and "VUPVAL" or "VLOCAL";
	t.k = "VINDEXED";
end;
function code.constfolding(self, op, e1, e2)
	local r;
	if not self:isnumeral(e1) or not self:isnumeral(e2) then
		return false;
	end;
	local v1 = e1.nval;
	local v2 = e2.nval;
	if op == "OP_ADD" then
		r = self:numadd(v1, v2);
	elseif op == "OP_SUB" then
		r = self:numsub(v1, v2);
	elseif op == "OP_MUL" then
		r = self:nummul(v1, v2);
	elseif op == "OP_DIV" then
		if v2 == 0 then
			return false;
		end;
		r = self:numdiv(v1, v2);
	elseif op == "OP_MOD" then
		if v2 == 0 then
			return false;
		end;
		r = self:nummod(v1, v2);
	elseif op == "OP_POW" then
		r = self:numpow(v1, v2);
	elseif op == "OP_IDIV" then
		r = self:numidiv(v1, v2);
	elseif op == "OP_BAND" then
		r = self:numband(v1, v2);
	elseif op == "OP_BOR" then
		r = self:numbor(v1, v2);
	elseif op == "OP_BXOR" then
		r = self:numbxor(v1, v2);
	elseif op == "OP_SHR" then
		r = self:numshr(v1, v2);
	elseif op == "OP_SHL" then
		r = self:numshl(v1, v2);
	elseif op == "OP_BNOT" then
		r = self:numbnot(v1);
	elseif op == "OP_UNM" then
		r = self:numunm(v1);
	elseif op == "OP_LEN" then
		return false;
	else
		assert(0);
		r = 0;
	end;
	if self:numisnan(r) then
		return false;
	end;
	e1.nval = r;
	return true;
end;
function code.codearith(self, fs, op, e1, e2)
	if op == "OP_GETTABUP" or op == "OP_SETTABUP" then
		if not fs.upvalues[e1.info] then
			lex:syntaxerror(fs.ls, "invalid upvalue index");
		end;
		local A, B, C;
		if op == "OP_GETTABUP" then
			A = e1.info;
			B = e2.info;
			C = e2.aux;
		else
			A = e1.info;
			B = e2.info;
			C = e2.aux;
		end;
		return self:codeABC(fs, op, A, B, C);
	end;
	if self:constfolding(op, e1, e2) then
		return;
	else
		local o2 = (op ~= "OP_UNM" and (op ~= "OP_LEN" and op ~= "OP_BNOT")) and self:exp2RK(fs, e2) or 0;
		local o1 = self:exp2RK(fs, e1);
		if o1 > o2 then
			self:freeexp(fs, e1);
			self:freeexp(fs, e2);
		else
			self:freeexp(fs, e2);
			self:freeexp(fs, e1);
		end;
		e1.info = self:codeABC(fs, op, 0, o1, o2);
		e1.k = "VRELOCABLE";
	end;
end;
function code.codecomp(self, fs, op, cond, e1, e2)
	local o1 = self:exp2RK(fs, e1);
	local o2 = self:exp2RK(fs, e2);
	self:freeexp(fs, e2);
	self:freeexp(fs, e1);
	if cond == 0 and op ~= "OP_EQ" then
		o1, o2 = o2, o1;
		cond = 1;
	end;
	e1.info = self:condjump(fs, op, cond, o1, o2);
	e1.k = "VJMP";
end;
function code.prefix(self, fs, op, e)
	local e2 = {};
	e2.t, e2.f = self.NO_JUMP, self.NO_JUMP;
	e2.k = "VKNUM";
	e2.nval = 0;
	if op == "OPR_MINUS" then
		if not self:isnumeral(e) then
			self:exp2anyreg(fs, e);
		end;
		self:codearith(fs, "OP_UNM", e, e2);
	elseif op == "OPR_BNOT" then
		if not self:isnumeral(e) then
			self:exp2anyreg(fs, e);
		end;
		self:codearith(fs, "OP_BNOT", e, e2);
	elseif op == "OPR_NOT" then
		self:codenot(fs, e);
	elseif op == "OPR_LEN" then
		self:exp2anyreg(fs, e);
		self:codearith(fs, "OP_LEN", e, e2);
	else
		assert(0);
	end;
end;
function code.infix(self, fs, op, v)
	if op == "OPR_AND" then
		self:goiftrue(fs, v);
	elseif op == "OPR_OR" then
		self:goiffalse(fs, v);
	elseif op == "OPR_CONCAT" then
		self:exp2nextreg(fs, v);
	elseif op == "OPR_ADD" or op == "OPR_SUB" or op == "OPR_MUL" or op == "OPR_DIV" or op == "OPR_MOD" or op == "OPR_POW" or op == "OPR_IDIV" or op == "OPR_BAND" or op == "OPR_BOR" or op == "OPR_BXOR" or op == "OPR_SHR" or op == "OPR_SHL" then
		if not self:isnumeral(v) then
			self:exp2RK(fs, v);
		end;
	else
		self:exp2RK(fs, v);
	end;
end;
code.arith_op = {
		OPR_ADD = "OP_ADD",
		OPR_SUB = "OP_SUB",
		OPR_MUL = "OP_MUL",
		OPR_DIV = "OP_DIV",
		OPR_MOD = "OP_MOD",
		OPR_POW = "OP_POW",
		OPR_IDIV = "OP_IDIV",
		OPR_BAND = "OP_BAND",
		OPR_BOR = "OP_BOR",
		OPR_BXOR = "OP_BXOR",
		OPR_SHR = "OP_SHR",
		OPR_SHL = "OP_SHL",
	};
code.comp_op = {
		OPR_EQ = "OP_EQ",
		OPR_NE = "OP_EQ",
		OPR_LT = "OP_LT",
		OPR_LE = "OP_LE",
		OPR_GT = "OP_LT",
		OPR_GE = "OP_LE",
	};
code.comp_cond = {
		OPR_EQ = 1,
		OPR_NE = 0,
		OPR_LT = 1,
		OPR_LE = 1,
		OPR_GT = 0,
		OPR_GE = 0,
	};
function code.posfix(self, fs, op, e1, e2)
	local function copyexp(e1, e2)
		e1.k = e2.k;
		e1.info = e2.info;
		e1.aux = e2.aux;
		e1.nval = e2.nval;
		e1.t = e2.t;
		e1.f = e2.f;
	end;
	if op == "OPR_AND" then
		assert(e1.t == self.NO_JUMP);
		self:dischargevars(fs, e2);
		e2.f = self:concat(fs, e2.f, e1.f);
		copyexp(e1, e2);
	elseif op == "OPR_OR" then
		assert(e1.f == self.NO_JUMP);
		self:dischargevars(fs, e2);
		e2.t = self:concat(fs, e2.t, e1.t);
		copyexp(e1, e2);
	elseif op == "OPR_CONCAT" then
		self:exp2val(fs, e2);
		if e2.k == "VRELOCABLE" and opcodes:GET_OPCODE(self:getcode(fs, e2)) == "OP_CONCAT" then
			assert(e1.info == opcodes:GETARG_B(self:getcode(fs, e2)) - 1);
			self:freeexp(fs, e1);
			opcodes:SETARG_B(self:getcode(fs, e2), e1.info);
			e1.k = "VRELOCABLE";
			e1.info = e2.info;
		else
			self:exp2nextreg(fs, e2);
			self:codearith(fs, "OP_CONCAT", e1, e2);
		end;
	else
		local arith = self.arith_op[op];
		if arith then
			self:codearith(fs, arith, e1, e2);
		else
			local comp = self.comp_op[op];
			if comp then
				self:codecomp(fs, comp, self.comp_cond[op], e1, e2);
			else
				assert(0);
			end;
		end;
	end;
end;
function code.fixline(self, fs, line)
	fs.f.lineinfo[fs.pc - 1] = line;
end;
function code.code(self, fs, i, line)
	local f = fs.f;
	self:dischargejpc(fs);
	self:growvector(fs.L, f.code, fs.pc, f.sizecode, nil, self.MAX_INT, "code size overflow");
	f.code[fs.pc] = i;
	self:growvector(fs.L, f.lineinfo, fs.pc, f.sizelineinfo, nil, self.MAX_INT, "code size overflow");
	f.lineinfo[fs.pc] = line;
	local pc = fs.pc;
	fs.pc = fs.pc + 1;
	return pc;
end;
function code.codeABC(self, fs, o, a, b, c)
	assert(opcodes:getOpMode(o) == opcodes.OpMode.iABC);
	assert(opcodes:getBMode(o) ~= opcodes.OpArgMask.OpArgN or b == 0);
	assert(opcodes:getCMode(o) ~= opcodes.OpArgMask.OpArgN or c == 0);
	return self:code(fs, opcodes:CREATE_ABC(o, a, b, c), fs.ls.lastline);
end;
function code.codeABx(self, fs, o, a, bc)
	if o == "OP_LOADK" and bc > opcodes.MAXARG_Bx then
		local inst = self:CREATE_ABx("OP_LOADKX", a, 0);
		fs.f.code[fs.pc] = inst;
		self:code(fs, self:CREATE_Ax("OP_EXTRAARG", bc), fs.ls.lastline);
	else
		assert(opcodes:getOpMode(o) == opcodes.OpMode.iABx or opcodes:getOpMode(o) == opcodes.OpMode.iAsBx);
		assert(opcodes:getCMode(o) == opcodes.OpArgMask.OpArgN);
	end;
	return self:code(fs, opcodes:CREATE_ABx(o, a, bc), fs.ls.lastline);
end;
function code.setlist(self, fs, base, nelems, tostore)
	local c = math.floor((nelems - 1) / opcodes.LFIELDS_PER_FLUSH) + 1;
	local b = tostore == self.LUA_MULTRET and 0 or tostore;
	assert(tostore ~= 0);
	if c <= opcodes.MAXARG_C then
		self:codeABC(fs, "OP_SETLIST", base, b, c);
	else
		self:codeABC(fs, "OP_SETLIST", base, b, 0);
		self:code(fs, opcodes:CREATE_Inst(c), fs.ls.lastline);
	end;
	fs.freereg = base + 1;
end;
return code;