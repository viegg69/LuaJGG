local luac = require("luac");
local lex = require("lex");
local opcodes = require("opcodes");
local code = require("code");
local vm = require("vm");
local parser = {};
parser.vm = vm;
local LuaState = {};
parser.LUA_QS = lex.LUA_QS or "\'%s\'";
parser.SHRT_MAX = 32767;
parser.LUAI_MAXVARS = 200;
parser.LUAI_MAXUPVALUES = 60;
parser.MAX_INT = lex.MAX_INT or 2147483645;
parser.LUAI_MAXCCALLS = 200;
parser.VARARG_HASARG = 1;
parser.HASARG_MASK = 2;
parser.VARARG_ISVARARG = 2;
parser.VARARG_NEEDSARG = 4;
parser.LUA_MULTRET = -1;
function parser.LUA_QL(self, x)
	return "\'" .. (x .. "\'");
end;
function parser.growvector(self, L, v, nelems, size, t, limit, e)
	if nelems >= limit then
		error(e);
	end;
end;
function parser.newproto(self, L)
	local f = {};
	f.k = {};
	f.sizek = 0;
	f.p = {};
	f.sizep = 0;
	f.code = {};
	f.sizecode = 0;
	f.sizelineinfo = 0;
	f.sizeupvalues = 0;
	f.nups = 0;
	f.upvalues = {};
	f.numparams = 0;
	f.is_vararg = 0;
	f.maxstacksize = 0;
	f.lineinfo = {};
	f.sizelocvars = 0;
	f.locvars = {};
	f.lineDefined = 0;
	f.lastlinedefined = 0;
	f.source = nil;
	return f;
end;
function parser.int2fb(self, x)
	local e = 0;
	while x >= 16 do
		x = math.floor((x + 1) / 2);
		e = e + 1;
	end;
	if x < 8 then
		return x;
	else
		return (e + 1) * 8 + (x - 8);
	end;
end;
function parser.hasmultret(self, k)
	return k == "VCALL" or k == "VVARARG";
end;
function parser.getlocvar(self, fs, i)
	return fs.f.locvars[fs.actvar[i]];
end;
function parser.checklimit(self, fs, v, l, m)
	if v > l then
		self:errorlimit(fs, l, m);
	end;
end;
function parser.anchor_token(self, ls)
	if ls.t.token == "TK_NAME" or ls.t.token == "TK_STRING" then
 
	end;
end;
function parser.error_expected(self, ls, token)
	lex:syntaxerror(ls, string.format(self.LUA_QS .. " expected", lex:token2str(ls, token)));
end;
function parser.errorlimit(self, fs, limit, what)
	local msg = fs.f.linedefined == 0 and string.format("main function has more than %d %s", limit, what) or string.format("function at line %d has more than %d %s", fs.f.linedefined, limit, what);
	lex:lexerror(fs.ls, msg, 0);
end;
function parser.testnext(self, ls, c)
	if ls.t.token == c then
		lex:next(ls);
		return true;
	else
		return false;
	end;
end;
function parser.check(self, ls, c)
	if ls.t.token ~= c then
		self:error_expected(ls, c);
	end;
end;
function parser.checknext(self, ls, c)
	self:check(ls, c);
	lex:next(ls);
end;
function parser.check_condition(self, ls, c, msg)
	if not c then
		lex:syntaxerror(ls, msg);
	end;
end;
function parser.check_match(self, ls, what, who, where)
	if not self:testnext(ls, what) then
		if where == ls.linenumber then
			self:error_expected(ls, what);
		else
			lex:syntaxerror(ls, string.format(self.LUA_QS .. (" expected (to close " .. (self.LUA_QS .. " at line %d)")), lex:token2str(ls, what), lex:token2str(ls, who), where));
		end;
	end;
end;
function parser.str_checkname(self, ls)
	self:check(ls, "TK_NAME");
	local ts = ls.t.seminfo;
	lex:next(ls);
	return ts;
end;
function parser.init_exp(self, e, k, i)
	e.f, e.t = code.NO_JUMP, code.NO_JUMP;
	e.k = k;
	e.info = i;
end;
function parser.codestring(self, ls, e, s)
	self:init_exp(e, "VK", code:stringK(ls.fs, s));
end;
function parser.checkname(self, ls, e)
	self:codestring(ls, e, self:str_checkname(ls));
end;
function parser.registerlocalvar(self, ls, varname)
	local fs = ls.fs;
	local f = fs.f;
	self:growvector(ls.L, f.locvars, fs.nlocvars, f.sizelocvars, nil, self.SHRT_MAX, "too many local variables");
	f.locvars[fs.nlocvars] = {};
	f.locvars[fs.nlocvars].varname = varname;
	local nlocvars = fs.nlocvars;
	fs.nlocvars = fs.nlocvars + 1;
	return nlocvars;
end;
function parser.new_localvarliteral(self, ls, v, n)
	self:new_localvar(ls, v, n);
end;
function parser.new_localvar(self, ls, name, n)
	local fs = ls.fs;
	self:checklimit(fs, (fs.nactvar + n) + 1, self.LUAI_MAXVARS, "local variables");
	fs.actvar[fs.nactvar + n] = self:registerlocalvar(ls, name);
end;
function parser.adjustlocalvars(self, ls, nvars)
	local fs = ls.fs;
	fs.nactvar = fs.nactvar + nvars;
	for i = nvars, 1, -1 do
		(self:getlocvar(fs, fs.nactvar - i)).startpc = fs.pc;
	end;
end;
function parser.removevars(self, ls, tolevel)
	local fs = ls.fs;
	while fs.nactvar > tolevel do
		fs.nactvar = fs.nactvar - 1;
		(self:getlocvar(fs, fs.nactvar)).endpc = fs.pc;
	end;
end;
function parser.searchupvalue(self, fs, name)
	for i = 0, fs.f.nups - 1, 1 do
		if fs.f.upvalues[i] == name then
			return i;
		end;
	end;
	return -1;
end;
function parser.indexupvalue(self, fs, name, v)
	local f = fs.f;
	for i = 0, f.nups - 1, 1 do
		if fs.upvalues[i].k == v.k and fs.upvalues[i].info == v.info then
			assert(f.upvalues[i] == name);
			return i;
		end;
	end;
	self:checklimit(fs, f.nups + 1, self.LUAI_MAXUPVALUES, "upvalues");
	self:growvector(fs.L, f.upvalues, f.nups, f.sizeupvalues, nil, self.MAX_INT, "");
	f.upvalues[f.nups] = name;
	assert(v.k == "VLOCAL" or v.k == "VUPVAL");
	fs.upvalues[f.nups] = { k = v.k, info = v.info };
	local nups = f.nups;
	f.nups = f.nups + 1;
	return nups;
end;
function parser.searchvar(self, fs, n)
	for i = fs.nactvar - 1, 0, -1 do
		if n == (self:getlocvar(fs, i)).varname then
			return i;
		end;
	end;
	return -1;
end;
function parser.markupval(self, fs, level)
	local bl = fs.bl;
	while bl and bl.nactvar > level do
		bl = bl.previous;
	end;
	if bl then
		bl.upval = true;
	end;
end;
function parser.singlevaraux(self, fs, n, var, base)
	if fs == nil then
		return "VVOID";
	else
		local v = self:searchvar(fs, n);
		if v >= 0 then
			self:init_exp(var, "VLOCAL", v);
			if base == 0 then
				self:markupval(fs, v);
			end;
			return "VLOCAL";
		else
			local idx = self:searchupvalue(fs, n);
			if idx < 0 then
				if self:singlevaraux(fs.prev, n, var, 0) == "VVOID" then
					return "VVOID";
				end;
				idx = self:indexupvalue(fs, n, var);
			end;
			self:init_exp(var, "VUPVAL", idx);
			return "VUPVAL";
		end;
	end;
end;
function parser.singlevar(self, ls, var)
	local varname = self:str_checkname(ls);
	local fs = ls.fs;
	if self:singlevaraux(fs, varname, var, 1) == "VVOID" then
		self:singlevaraux(fs, "_ENV", var, 1);
		assert(var.k == "VLOCAL" or var.k == "VUPVAL");
		local key = {};
		self:codestring(ls, key, varname);
		code:indexed(fs, var, key);
	end;
end;
function parser.adjust_assign(self, ls, nvars, nexps, e)
	local fs = ls.fs;
	local extra = nvars - nexps;
	if self:hasmultret(e.k) then
		extra = extra + 1;
		if extra <= 0 then
			extra = 0;
		end;
		code:setreturns(fs, e, extra);
		if extra > 1 then
			code:reserveregs(fs, extra - 1);
		end;
	else
		if e.k ~= "VVOID" then
			code:exp2nextreg(fs, e);
		end;
		if extra > 0 then
			local reg = fs.freereg;
			code:reserveregs(fs, extra);
			code:_nil(fs, reg, extra);
		end;
	end;
end;
function parser.enterlevel(self, ls)
	ls.L.nCcalls = ls.L.nCcalls + 1;
	if ls.L.nCcalls > self.LUAI_MAXCCALLS then
		lex:lexerror(ls, "chunk has too many syntax levels", 0);
	end;
end;
function parser.leavelevel(self, ls)
	ls.L.nCcalls = ls.L.nCcalls - 1;
end;
function parser.enterblock(self, fs, bl, isbreakable)
	bl.breaklist = code.NO_JUMP;
	bl.isbreakable = isbreakable;
	bl.nactvar = fs.nactvar;
	bl.upval = false;
	bl.previous = fs.bl;
	fs.bl = bl;
	assert(fs.freereg == fs.nactvar);
end;
function parser.leaveblock(self, fs)
	local bl = fs.bl;
	fs.bl = bl.previous;
	self:removevars(fs.ls, bl.nactvar);
	if bl.upval then
		local j = code:jump(fs);
		code:patchclose(fs, j, bl.nactvar);
		code:patchtohere(fs, j);
	end;
	assert(not bl.isbreakable or not bl.upval);
	assert(bl.nactvar == fs.nactvar);
	fs.freereg = fs.nactvar;
	code:patchtohere(fs, bl.breaklist);
end;
function parser.pushclosure(self, ls, func, v)
	local fs = ls.fs;
	local f = fs.f;
	self:growvector(ls.L, f.p, fs.np, f.sizep, nil, opcodes.MAXARG_Bx, "constant table overflow");
	f.p[fs.np] = func.f;
	fs.np = fs.np + 1;
	self:init_exp(v, "VRELOCABLE", code:codeABx(fs, "OP_CLOSURE", 0, fs.np - 1));
	for i = 0, func.f.nups - 1, 1 do
		local o = func.upvalues[i].k == "VLOCAL" and "OP_MOVE" or "OP_GETUPVAL";
		code:codeABC(fs, o, 0, func.upvalues[i].info, 0);
	end;
end;
function parser.open_func(self, ls, fs)
	local L = ls.L;
	local f = self:newproto(ls.L);
	fs.f = f;
	fs.prev = ls.fs;
	fs.ls = ls;
	fs.L = L;
	ls.fs = fs;
	fs.pc = 0;
	fs.lasttarget = -1;
	fs.jpc = code.NO_JUMP;
	fs.freereg = 0;
	fs.nk = 0;
	fs.np = 0;
	fs.nlocvars = 0;
	fs.nactvar = 0;
	fs.bl = nil;
	f.source = ls.source;
	f.maxstacksize = 2;
	fs.h = {};
end;
function parser.base_close_func(self, ls)
	local L = ls.L;
	local fs = ls.fs;
	local f = fs.f;
	self:removevars(ls, 0);
	code:ret(fs, 0, 0);
	f.sizecode = fs.pc;
	f.sizelineinfo = fs.pc;
	f.sizek = fs.nk;
	f.sizep = fs.np;
	f.sizelocvars = fs.nlocvars;
	f.sizeupvalues = f.nups;
	assert(fs.bl == nil);
	ls.fs = fs.prev;
	if fs then
		self:anchor_token(ls);
	end;
end;
local labels = {};
local gotos = {};
function parser.close_func(self, ls)
	self:base_close_func(ls);
	for label, goto_list in pairs(gotos) do
		for _, goto_pc in ipairs(goto_list) do
			lex:syntaxerror(ls, "no visible label \'" .. (label .. "\' for goto"));
		end;
	end;
end;
function parser.parser(self, L, z, buff, name)
	local lexstate = {};
	lexstate.t = {};
	lexstate.lookahead = {};
	local funcstate = {};
	funcstate.upvalues = {};
	funcstate.actvar = {};
	L.nCcalls = 0;
	lexstate.buff = buff;
	lex:setinput(L, lexstate, z, name);
	self:open_func(lexstate, funcstate);
	funcstate.f.is_vararg = 1;
	local v = {};
	self:init_exp(v, "VLOCAL", 0);
	self:indexupvalue(funcstate, "_ENV", v);
	lex:next(lexstate);
	self:chunk(lexstate);
	self:check(lexstate, "TK_EOS");
	self:close_func(lexstate);
	assert(funcstate.prev == nil);
	assert(lexstate.fs == nil);
	return funcstate.f;
end;
function parser.field(self, ls, v)
	local fs = ls.fs;
	local key = {};
	code:exp2anyreg(fs, v);
	lex:next(ls);
	self:checkname(ls, key);
	code:indexed(fs, v, key);
end;
function parser.yindex(self, ls, v)
	lex:next(ls);
	self:expr(ls, v);
	code:exp2val(ls.fs, v);
	self:checknext(ls, "]");
end;
function parser.recfield(self, ls, cc)
	local fs = ls.fs;
	local reg = ls.fs.freereg;
	local key, val = {}, {};
	if ls.t.token == "TK_NAME" then
		self:checklimit(fs, cc.nh, self.MAX_INT, "items in a constructor");
		self:checkname(ls, key);
	else
		self:yindex(ls, key);
	end;
	cc.nh = cc.nh + 1;
	self:checknext(ls, "=");
	local rkkey = code:exp2RK(fs, key);
	self:expr(ls, val);
	code:codeABC(fs, "OP_SETTABLE", cc.t.info, rkkey, code:exp2RK(fs, val));
	fs.freereg = reg;
end;
function parser.closelistfield(self, fs, cc)
	if cc.v.k == "VVOID" then
		return;
	end;
	code:exp2nextreg(fs, cc.v);
	cc.v.k = "VVOID";
	if cc.tostore == opcodes.LFIELDS_PER_FLUSH then
		code:setlist(fs, cc.t.info, cc.na, cc.tostore);
		cc.tostore = 0;
	end;
end;
function parser.lastlistfield(self, fs, cc)
	if cc.tostore == 0 then
		return;
	end;
	if self:hasmultret(cc.v.k) then
		code:setmultret(fs, cc.v);
		code:setlist(fs, cc.t.info, cc.na, self.LUA_MULTRET);
		cc.na = cc.na - 1;
	else
		if cc.v.k ~= "VVOID" then
			code:exp2nextreg(fs, cc.v);
		end;
		code:setlist(fs, cc.t.info, cc.na, cc.tostore);
	end;
end;
function parser.listfield(self, ls, cc)
	self:expr(ls, cc.v);
	self:checklimit(ls.fs, cc.na, self.MAX_INT, "items in a constructor");
	cc.na = cc.na + 1;
	cc.tostore = cc.tostore + 1;
end;
function parser.constructor(self, ls, t)
	local fs = ls.fs;
	local line = ls.linenumber;
	local pc = code:codeABC(fs, "OP_NEWTABLE", 0, 0, 0);
	local cc = {};
	cc.v = {};
	cc.na, cc.nh, cc.tostore = 0, 0, 0;
	cc.t = t;
	self:init_exp(t, "VRELOCABLE", pc);
	self:init_exp(cc.v, "VVOID", 0);
	code:exp2nextreg(ls.fs, t);
	self:checknext(ls, "{");
	repeat
		assert(cc.v.k == "VVOID" or cc.tostore > 0);
		if ls.t.token == "}" then
			break;
		end;
		self:closelistfield(fs, cc);
		local c = ls.t.token;
		if c == "TK_NAME" then
			lex:lookahead(ls);
			if ls.lookahead.token ~= "=" then
				self:listfield(ls, cc);
			else
				self:recfield(ls, cc);
			end;
		elseif c == "[" then
			self:recfield(ls, cc);
		else
			self:listfield(ls, cc);
		end;
	until not self:testnext(ls, ",") and not self:testnext(ls, ";");
	self:check_match(ls, "}", "{", line);
	self:lastlistfield(fs, cc);
	opcodes:SETARG_B(fs.f.code[pc], self:int2fb(cc.na));
	opcodes:SETARG_C(fs.f.code[pc], self:int2fb(cc.nh));
end;
function parser.parlist(self, ls)
	local fs = ls.fs;
	local f = fs.f;
	local nparams = 0;
	f.is_vararg = 0;
	if ls.t.token ~= ")" then
		repeat
			local c = ls.t.token;
			if c == "TK_NAME" then
				self:new_localvar(ls, self:str_checkname(ls), nparams);
				nparams = nparams + 1;
			elseif c == "TK_DOTS" then
				lex:next(ls);
				self:new_localvarliteral(ls, "arg", nparams);
				nparams = nparams + 1;
				f.is_vararg = self.VARARG_HASARG + self.VARARG_NEEDSARG;
				f.is_vararg = f.is_vararg + self.VARARG_ISVARARG;
			else
				lex:syntaxerror(ls, "<name> or " .. (self:LUA_QL("...") .. " expected"));
			end;
		until f.is_vararg ~= 0 or not self:testnext(ls, ",");
	end;
	self:adjustlocalvars(ls, nparams);
	f.numparams = fs.nactvar - f.is_vararg % self.HASARG_MASK;
	code:reserveregs(fs, fs.nactvar);
end;
function parser.body(self, ls, e, needself, line)
	local new_fs = {};
	new_fs.upvalues = {};
	new_fs.actvar = {};
	self:open_func(ls, new_fs);
	new_fs.f.lineDefined = line;
	self:checknext(ls, "(");
	if needself then
		self:new_localvarliteral(ls, "self", 0);
		self:adjustlocalvars(ls, 1);
	end;
	self:parlist(ls);
	self:checknext(ls, ")");
	self:chunk(ls);
	new_fs.f.lastlinedefined = ls.linenumber;
	self:check_match(ls, "TK_END", "TK_FUNCTION", line);
	self:close_func(ls);
	self:pushclosure(ls, new_fs, e);
end;
function parser.explist1(self, ls, v)
	local n = 1;
	self:expr(ls, v);
	while self:testnext(ls, ",") do
		code:exp2nextreg(ls.fs, v);
		self:expr(ls, v);
		n = n + 1;
	end;
	return n;
end;
function parser.funcargs(self, ls, f)
	local fs = ls.fs;
	local args = {};
	local nparams;
	local line = ls.linenumber;
	local c = ls.t.token;
	if c == "(" then
		if line ~= ls.lastline then
			lex:syntaxerror(ls, "ambiguous syntax (function call x new statement)");
		end;
		lex:next(ls);
		if ls.t.token == ")" then
			args.k = "VVOID";
		else
			self:explist1(ls, args);
			code:setmultret(fs, args);
		end;
		self:check_match(ls, ")", "(", line);
	elseif c == "{" then
		self:constructor(ls, args);
	elseif c == "TK_STRING" then
		self:codestring(ls, args, ls.t.seminfo);
		lex:next(ls);
	else
		lex:syntaxerror(ls, "function arguments expected");
		return;
	end;
	assert(f.k == "VNONRELOC");
	local base = f.info;
	if self:hasmultret(args.k) then
		nparams = self.LUA_MULTRET;
	else
		if args.k ~= "VVOID" then
			code:exp2nextreg(fs, args);
		end;
		nparams = fs.freereg - (base + 1);
	end;
	self:init_exp(f, "VCALL", code:codeABC(fs, "OP_CALL", base, nparams + 1, 2));
	code:fixline(fs, line);
	fs.freereg = base + 1;
end;
function parser.prefixexp(self, ls, v)
	local c = ls.t.token;
	if c == "(" then
		local line = ls.linenumber;
		lex:next(ls);
		self:expr(ls, v);
		self:check_match(ls, ")", "(", line);
		code:dischargevars(ls.fs, v);
	elseif c == "TK_NAME" then
		self:singlevar(ls, v);
		if v.k == "VUPVAL" then
			local key = {};
		end;
	else
		lex:syntaxerror(ls, "unexpected symbol");
	end;
	return;
end;
function parser.primaryexp(self, ls, v)
	local fs = ls.fs;
	self:prefixexp(ls, v);
	while true do
		local c = ls.t.token;
		if c == "." then
			self:field(ls, v);
		elseif c == "[" then
			local key = {};
			code:exp2anyregup(fs, v);
			self:yindex(ls, key);
			code:indexed(fs, v, key);
		elseif c == ":" then
			local key = {};
			lex:next(ls);
			self:checkname(ls, key);
			code:_self(fs, v, key);
			self:funcargs(ls, v);
		elseif c == "(" or c == "TK_STRING" or c == "{" then
			code:exp2nextreg(fs, v);
			self:funcargs(ls, v);
		else
			return;
		end;
	end;
end;
function parser.simpleexp(self, ls, v)
	local c = ls.t.token;
	if c == "TK_NUMBER" then
		self:init_exp(v, "VKNUM", 0);
		v.nval = ls.t.seminfo;
	elseif c == "TK_STRING" then
		self:codestring(ls, v, ls.t.seminfo);
	elseif c == "TK_NIL" then
		self:init_exp(v, "VNIL", 0);
	elseif c == "TK_TRUE" then
		self:init_exp(v, "VTRUE", 0);
	elseif c == "TK_FALSE" then
		self:init_exp(v, "VFALSE", 0);
	elseif c == "TK_DOTS" then
		local fs = ls.fs;
		self:check_condition(ls, fs.f.is_vararg ~= 0, "cannot use " .. (self:LUA_QL("...") .. " outside a vararg function"));
		local is_vararg = fs.f.is_vararg;
		if is_vararg >= self.VARARG_NEEDSARG then
			fs.f.is_vararg = is_vararg - self.VARARG_NEEDSARG;
		end;
		self:init_exp(v, "VVARARG", code:codeABC(fs, "OP_VARARG", 0, 1, 0));
	elseif c == "{" then
		self:constructor(ls, v);
		return;
	elseif c == "TK_FUNCTION" then
		lex:next(ls);
		self:body(ls, v, false, ls.linenumber);
		return;
	else
		self:primaryexp(ls, v);
		return;
	end;
	lex:next(ls);
end;
function parser.getunopr(self, op)
	if op == "TK_NOT" then
		return "OPR_NOT";
	elseif op == "-" then
		return "OPR_MINUS";
	elseif op == "#" then
		return "OPR_LEN";
	elseif op == "~" then
		return "OPR_BNOT";
	else
		return "OPR_NOUNOPR";
	end;
end;
parser.getbinopr_table = {
		["+"] = "OPR_ADD",
		["-"] = "OPR_SUB",
		["*"] = "OPR_MUL",
		["/"] = "OPR_DIV",
		["%"] = "OPR_MOD",
		["^"] = "OPR_POW",
		TK_IDIV = "OPR_IDIV",
		["&"] = "OPR_BAND",
		["|"] = "OPR_BOR",
		["~"] = "OPR_BXOR",
		TK_SHR = "OPR_SHR",
		TK_SHL = "OPR_SHL",
		TK_CONCAT = "OPR_CONCAT",
		TK_NE = "OPR_NE",
		TK_EQ = "OPR_EQ",
		["<"] = "OPR_LT",
		TK_LE = "OPR_LE",
		[">"] = "OPR_GT",
		TK_GE = "OPR_GE",
		TK_AND = "OPR_AND",
		TK_OR = "OPR_OR",
	};
function parser.getbinopr(self, op)
	local opr = self.getbinopr_table[op];
	if opr then
		return opr;
	else
		return "OPR_NOBINOPR";
	end;
end;
parser.priority = {
		{ 6, 6 },
		{ 6, 6 },
		{ 7, 7 },
		{ 7, 7 },
		{ 7, 7 },
		{ 7, 7 },
		{ 7, 7 },
		{ 7, 7 },
		{ 7, 7 },
		{ 7, 7 },
		{ 7, 7 },
		{ 10, 9 },
		{ 5, 4 },
		{ 3, 3 },
		{ 3, 3 },
		{ 3, 3 },
		{ 3, 3 },
		{ 3, 3 },
		{ 3, 3 },
		{ 2, 2 },
		{ 1, 1 },
	};
parser.UNARY_PRIORITY = 8;
function parser.subexpr(self, ls, v, limit)
	self:enterlevel(ls);
	local uop = self:getunopr(ls.t.token);
	if uop ~= "OPR_NOUNOPR" then
		lex:next(ls);
		self:subexpr(ls, v, self.UNARY_PRIORITY);
		code:prefix(ls.fs, uop, v);
	else
		self:simpleexp(ls, v);
	end;
	local op = self:getbinopr(ls.t.token);
	while op ~= "OPR_NOBINOPR" and self.priority[code.BinOpr[op] + 1][1] > limit do
		local v2 = {};
		lex:next(ls);
		code:infix(ls.fs, op, v);
		local nextop = self:subexpr(ls, v2, self.priority[code.BinOpr[op] + 1][2]);
		code:posfix(ls.fs, op, v, v2);
		op = nextop;
	end;
	self:leavelevel(ls);
	return op;
end;
function parser.expr(self, ls, v)
	self:subexpr(ls, v, 0);
end;
function parser.block_follow(self, token)
	if token == "TK_ELSE" or token == "TK_ELSEIF" or token == "TK_END" or token == "TK_UNTIL" or token == "TK_EOS" then
		return true;
	else
		return false;
	end;
end;
function parser.block(self, ls)
	local fs = ls.fs;
	local bl = {};
	self:enterblock(fs, bl, false);
	self:chunk(ls);
	assert(bl.breaklist == code.NO_JUMP);
	self:leaveblock(fs);
end;
function parser.check_conflict(self, ls, lh, v)
	local fs = ls.fs;
	local extra = fs.freereg;
	local conflict = false;
	while lh do
		if lh.v.k == "VINDEXED" then
			if lh.v.info == v.info then
				conflict = true;
				lh.v.ind_vt = "VLOCAL";
				lh.v.info = extra;
			end;
			if lh.v.aux == v.info then
				conflict = true;
				lh.v.aux = extra;
			end;
		end;
		lh = lh.prev;
	end;
	if conflict then
		local op = v.k == "VLOCAL" and "OP_MOVE" or "OP_GETUPVAL";
		print("parser:check_conflict:", op);
		code:codeABC(fs, "OP_MOVE", fs.freereg, v.info, 0);
		code:reserveregs(fs, 1);
	end;
end;
function parser.assignment(self, ls, lh, nvars)
	local e = {};
	local c = lh.v.k;
	self:check_condition(ls, c == "VLOCAL" or c == "VUPVAL" or c == "VVOID" or c == "VINDEXED", "syntax error");
	if self:testnext(ls, ",") then
		local nv = {};
		nv.v = {};
		nv.prev = lh;
		self:primaryexp(ls, nv.v);
		if nv.v.k ~= "VINDEXED" then
			self:check_conflict(ls, lh, nv.v);
		end;
		self:checklimit(ls.fs, nvars, self.LUAI_MAXCCALLS - ls.L.nCcalls, "variables in assignment");
		self:assignment(ls, nv, nvars + 1);
	else
		self:checknext(ls, "=");
		local nexps = self:explist1(ls, e);
		if nexps ~= nvars then
			self:adjust_assign(ls, nvars, nexps, e);
			if nexps > nvars then
				ls.fs.freereg = ls.fs.freereg - (nexps - nvars);
			end;
		else
			code:setoneret(ls.fs, e);
			code:storevar(ls.fs, lh.v, e);
			return;
		end;
	end;
	self:init_exp(e, "VNONRELOC", ls.fs.freereg - 1);
	code:storevar(ls.fs, lh.v, e);
end;
function parser.cond(self, ls)
	local v = {};
	self:expr(ls, v);
	if v.k == "VNIL" then
		v.k = "VFALSE";
	end;
	code:goiftrue(ls.fs, v);
	return v.f;
end;
function parser.labelstat(self, ls, line)
	local label = self:str_checkname(ls);
	local fs = ls.fs;
	if labels[label] then
		lex:syntaxerror(ls, "label \'" .. (label .. "\' already defined"));
	end;
	labels[label] = code:getlabel(fs);
	if gotos[label] then
		for _, goto_pc in ipairs(gotos[label]) do
			code:patchlist(fs, goto_pc, labels[label]);
		end;
		gotos[label] = nil;
	end;
	self:checknext(ls, "TK_DBCOLON");
end;
function parser.gotostat(self, ls)
	local label = self:str_checkname(ls);
	local fs = ls.fs;
	local goto_pc = code:jump(fs);
	if labels[label] then
		code:patchlist(fs, goto_pc, labels[label]);
	else
		gotos[label] = gotos[label] or {};
		table.insert(gotos[label], goto_pc);
	end;
end;
function parser.breakstat(self, ls)
	local fs = ls.fs;
	local bl = fs.bl;
	local upval = false;
	while bl and not bl.isbreakable do
		if bl.upval then
			upval = true;
		end;
		bl = bl.previous;
	end;
	if not bl then
		lex:syntaxerror(ls, "no loop to break");
	end;
	if upval then
		code:codeABC(fs, "OP_CLOSE", bl.nactvar, 0, 0);
	end;
	bl.breaklist = code:concat(fs, bl.breaklist, code:jump(fs));
end;
function parser.whilestat(self, ls, line)
	local fs = ls.fs;
	local bl = {};
	lex:next(ls);
	local whileinit = code:getlabel(fs);
	local condexit = self:cond(ls);
	self:enterblock(fs, bl, true);
	self:checknext(ls, "TK_DO");
	self:block(ls);
	code:patchlist(fs, code:jump(fs), whileinit);
	self:check_match(ls, "TK_END", "TK_WHILE", line);
	self:leaveblock(fs);
	code:patchtohere(fs, condexit);
end;
function parser.repeatstat(self, ls, line)
	local fs = ls.fs;
	local repeat_init = code:getlabel(fs);
	local bl1, bl2 = {}, {};
	self:enterblock(fs, bl1, true);
	self:enterblock(fs, bl2, false);
	lex:next(ls);
	self:chunk(ls);
	self:check_match(ls, "TK_UNTIL", "TK_REPEAT", line);
	local condexit = self:cond(ls);
	if not bl2.upval then
		self:leaveblock(fs);
		code:patchlist(ls.fs, condexit, repeat_init);
	else
		self:breakstat(ls);
		code:patchtohere(ls.fs, condexit);
		self:leaveblock(fs);
		code:patchlist(ls.fs, code:jump(fs), repeat_init);
	end;
	self:leaveblock(fs);
end;
function parser.exp1(self, ls)
	local e = {};
	self:expr(ls, e);
	local k = e.k;
	code:exp2nextreg(ls.fs, e);
	return k;
end;
function parser.forbody(self, ls, base, line, nvars, isnum)
	local bl = {};
	local fs = ls.fs;
	self:adjustlocalvars(ls, 3);
	self:checknext(ls, "TK_DO");
	local prep = isnum and code:codeAsBx(fs, "OP_FORPREP", base, code.NO_JUMP) or code:jump(fs);
	self:enterblock(fs, bl, false);
	self:adjustlocalvars(ls, nvars);
	code:reserveregs(fs, nvars);
	self:block(ls);
	self:leaveblock(fs);
	code:patchtohere(fs, prep);
	if isnum then
		endfor = code:codeAsBx(fs, "OP_FORLOOP", base, code.NO_JUMP);
	else
		code:codeABC(fs, "OP_TFORCALL", base, 0, nvars);
		code:fixline(fs, line);
		endfor = code:codeAsBx(fs, "OP_TFORLOOP", base + 2, code.NO_JUMP);
	end;
	code:fixline(fs, line);
	code:patchlist(fs, endfor, prep + 1);
end;
function parser.fornum(self, ls, varname, line)
	local fs = ls.fs;
	local base = fs.freereg;
	self:new_localvarliteral(ls, "(for index)", 0);
	self:new_localvarliteral(ls, "(for limit)", 1);
	self:new_localvarliteral(ls, "(for step)", 2);
	self:new_localvar(ls, varname, 3);
	self:checknext(ls, "=");
	self:exp1(ls);
	self:checknext(ls, ",");
	self:exp1(ls);
	if self:testnext(ls, ",") then
		self:exp1(ls);
	else
		code:codeABx(fs, "OP_LOADK", fs.freereg, code:numberK(fs, 1));
		code:reserveregs(fs, 1);
	end;
	self:forbody(ls, base, line, 1, true);
end;
function parser.forlist(self, ls, indexname)
	local fs = ls.fs;
	local e = {};
	local nvars = 0;
	local base = fs.freereg;
	self:new_localvarliteral(ls, "(for generator)", nvars);
	nvars = nvars + 1;
	self:new_localvarliteral(ls, "(for state)", nvars);
	nvars = nvars + 1;
	self:new_localvarliteral(ls, "(for control)", nvars);
	nvars = nvars + 1;
	self:new_localvar(ls, indexname, nvars);
	nvars = nvars + 1;
	while self:testnext(ls, ",") do
		self:new_localvar(ls, self:str_checkname(ls), nvars);
		nvars = nvars + 1;
	end;
	self:checknext(ls, "TK_IN");
	local line = ls.linenumber;
	self:adjust_assign(ls, 3, self:explist1(ls, e), e);
	code:checkstack(fs, 3);
	self:forbody(ls, base, line, nvars - 3, false);
end;
function parser.forstat(self, ls, line)
	local fs = ls.fs;
	local bl = {};
	self:enterblock(fs, bl, true);
	lex:next(ls);
	local varname = self:str_checkname(ls);
	local c = ls.t.token;
	if c == "=" then
		self:fornum(ls, varname, line);
	elseif c == "," or c == "TK_IN" then
		self:forlist(ls, varname);
	else
		lex:syntaxerror(ls, self:LUA_QL("=") .. (" or " .. (self:LUA_QL("in") .. " expected")));
	end;
	self:check_match(ls, "TK_END", "TK_FOR", line);
	self:leaveblock(fs);
end;
function parser.test_then_block(self, ls)
	lex:next(ls);
	local condexit = self:cond(ls);
	self:checknext(ls, "TK_THEN");
	self:block(ls);
	return condexit;
end;
function parser.ifstat(self, ls, line)
	local fs = ls.fs;
	local escapelist = code.NO_JUMP;
	local flist = self:test_then_block(ls);
	while ls.t.token == "TK_ELSEIF" do
		escapelist = code:concat(fs, escapelist, code:jump(fs));
		code:patchtohere(fs, flist);
		flist = self:test_then_block(ls);
	end;
	if ls.t.token == "TK_ELSE" then
		escapelist = code:concat(fs, escapelist, code:jump(fs));
		code:patchtohere(fs, flist);
		lex:next(ls);
		self:block(ls);
	else
		escapelist = code:concat(fs, escapelist, flist);
	end;
	code:patchtohere(fs, escapelist);
	self:check_match(ls, "TK_END", "TK_IF", line);
end;
function parser.localfunc(self, ls)
	local v, b = {}, {};
	local fs = ls.fs;
	self:new_localvar(ls, self:str_checkname(ls), 0);
	self:init_exp(v, "VLOCAL", fs.freereg);
	code:reserveregs(fs, 1);
	self:adjustlocalvars(ls, 1);
	self:body(ls, b, false, ls.linenumber);
	code:storevar(fs, v, b);
	(self:getlocvar(fs, fs.nactvar - 1)).startpc = fs.pc;
end;
function parser.localstat(self, ls)
	local nvars = 0;
	local nexps;
	local e = {};
	repeat
		self:new_localvar(ls, self:str_checkname(ls), nvars);
		nvars = nvars + 1;
	until not self:testnext(ls, ",");
	if self:testnext(ls, "=") then
		nexps = self:explist1(ls, e);
	else
		e.k = "VVOID";
		nexps = 0;
	end;
	self:adjust_assign(ls, nvars, nexps, e);
	self:adjustlocalvars(ls, nvars);
end;
function parser.funcname(self, ls, v)
	local needself = false;
	self:singlevar(ls, v);
	while ls.t.token == "." do
		self:field(ls, v);
	end;
	if ls.t.token == ":" then
		needself = true;
		self:field(ls, v);
	end;
	return needself;
end;
function parser.funcstat(self, ls, line)
	local v, b = {}, {};
	lex:next(ls);
	local needself = self:funcname(ls, v);
	self:body(ls, b, needself, line);
	code:storevar(ls.fs, v, b);
	code:fixline(ls.fs, line);
end;
function parser.exprstat(self, ls)
	local fs = ls.fs;
	local v = {};
	v.v = {};
	self:primaryexp(ls, v.v);
	if v.v.k == "VCALL" then
		opcodes:SETARG_C(code:getcode(fs, v.v), 1);
	else
		v.prev = nil;
		self:assignment(ls, v, 1);
	end;
end;
function parser.retstat(self, ls)
	local fs = ls.fs;
	local e = {};
	local first, nret;
	lex:next(ls);
	if self:block_follow(ls.t.token) or ls.t.token == ";" then
		first, nret = 0, 0;
	else
		nret = self:explist1(ls, e);
		if self:hasmultret(e.k) then
			code:setmultret(fs, e);
			if e.k == "VCALL" and nret == 1 then
				opcodes:SET_OPCODE(code:getcode(fs, e), "OP_TAILCALL");
				assert(opcodes:GETARG_A(code:getcode(fs, e)) == fs.nactvar);
			end;
			first = fs.nactvar;
			nret = self.LUA_MULTRET;
		else
			if nret == 1 then
				first = code:exp2anyreg(fs, e);
			else
				code:exp2nextreg(fs, e);
				first = fs.nactvar;
				assert(nret == fs.freereg - first);
			end;
		end;
	end;
	code:ret(fs, first, nret);
end;
function parser.statement(self, ls)
	local line = ls.linenumber;
	local c = ls.t.token;
	if c == "TK_IF" then
		self:ifstat(ls, line);
		return false;
	elseif c == "TK_GOTO" then
		lex:next(ls);
		self:gotostat(ls);
		return false;
	elseif c == "TK_DBCOLON" then
		lex:next(ls);
		self:labelstat(ls, line);
		return false;
	elseif c == "TK_WHILE" then
		self:whilestat(ls, line);
		return false;
	elseif c == "TK_DO" then
		lex:next(ls);
		self:block(ls);
		self:check_match(ls, "TK_END", "TK_DO", line);
		return false;
	elseif c == "TK_FOR" then
		self:forstat(ls, line);
		return false;
	elseif c == "TK_REPEAT" then
		self:repeatstat(ls, line);
		return false;
	elseif c == "TK_FUNCTION" then
		self:funcstat(ls, line);
		return false;
	elseif c == "TK_LOCAL" then
		lex:next(ls);
		if self:testnext(ls, "TK_FUNCTION") then
			self:localfunc(ls);
		else
			self:localstat(ls);
		end;
		return false;
	elseif c == "TK_RETURN" then
		self:retstat(ls);
		return true;
	elseif c == "TK_BREAK" then
		lex:next(ls);
		self:breakstat(ls);
		return true;
	else
		self:exprstat(ls);
		return false;
	end;
end;
function parser.chunk(self, ls)
	local islast = false;
	self:enterlevel(ls);
	while not islast and not self:block_follow(ls.t.token) do
		islast = self:statement(ls);
		self:testnext(ls, ";");
		assert(ls.fs.f.maxstacksize >= ls.fs.freereg and ls.fs.freereg >= ls.fs.nactvar);
		ls.fs.freereg = ls.fs.nactvar;
	end;
	self:leavelevel(ls);
end;
local n = {
		code = "instructions",
		k = "constants",
		p = "proto",
		maxstacksize = "maxStack",
		locvars = "locals",
		varname = "name",
		is_vararg = "isvararg",
		numparams = "nparam",
		lineinfo = "sourceLines",
		source = "name",
		lastlinedefined = "lastLineDefined",
	};
function fixn(f)
	for i, v in pairs(f) do
		if n[i] then
			f[n[i]] = v;
			f["size" .. i] = nil;
			f[i] = nil;
		end;
	end;
end;
function cp(f)
	local r = f;
	if f.p and f.p[0] then
		for i = 0, #f.p, 1 do
			cp(f.p[i]);
		end;
	end;
	if r.code and r.code[0] then
		for i = 0, #r.code, 1 do
			local v = r.code[i];
			v.OP = opcodes.opnames[v.OP];
			if v.Bx and v.Bx > 255 then
				v.Bx = opcodes:GETARG_sBx(v);
			end;
			r.code[i] = {
					v.OP,
					v.A,
					v.Bx or v.B,
					v.C,
				};
		end;
	end;
	if r.k and r.k[0] then
		for i = 0, #r.k, 1 do
			local v = r.k[i];
			r.k[i] = v.value;
		end;
	end;
	if r.locvars and r.locvars[0] then
		for i = 0, #r.locvars, 1 do
			local v = r.locvars[i];
			v.name = v.varname;
			v.varname = nil;
			r.locvars[i] = v;
		end;
	end;
	fixn(f);
end;
function copy(f)
	if f.p[0] then
		for i = 0, #f.p, 1 do
			cp(f.p[i]);
		end;
	end;
	cp(f);
	return f;
end;
parser.copy = false;
function parser.coppy(self, f)
	return copy(f);
end;
function parser.toLua(self)
	return tolua(copy(self.chunk));
end;
function parser.parse(self, source, name, cp)
	name = name or "parse";
	local zio = luac:init(luac:make_getF(source), nil);
	if not zio then
		return;
	end;
	local f = self:parser(LuaState, zio, nil, "@" .. name);
	if self.copy or cp then
		copy(f);
	end;
	self.chunk = f;
	vm.chunk = f;
	return self;
end;
return setmetatable({}, { __index = parser, __call = parser.parse });