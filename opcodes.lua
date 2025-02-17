local opcodes = {};
opcodes.OpMode = {
		iABC = 0,
		iABx = 1,
		iAsBx = 2,
		iAx = 3,
	};
opcodes.SIZE_C = 9;
opcodes.SIZE_B = 9;
opcodes.SIZE_Bx = opcodes.SIZE_C + opcodes.SIZE_B;
opcodes.SIZE_A = 8;
opcodes.SIZE_OP = 6;
opcodes.POS_OP = 0;
opcodes.POS_A = opcodes.POS_OP + opcodes.SIZE_OP;
opcodes.POS_C = opcodes.POS_A + opcodes.SIZE_A;
opcodes.POS_B = opcodes.POS_C + opcodes.SIZE_C;
opcodes.POS_Bx = opcodes.POS_C;
opcodes.MAXARG_Bx = math.ldexp(1, opcodes.SIZE_Bx) - 1;
opcodes.MAXARG_sBx = math.floor(opcodes.MAXARG_Bx / 2);
opcodes.MAXARG_A = math.ldexp(1, opcodes.SIZE_A) - 1;
opcodes.MAXARG_B = math.ldexp(1, opcodes.SIZE_B) - 1;
opcodes.MAXARG_C = math.ldexp(1, opcodes.SIZE_C) - 1;
function opcodes.GET_OPCODE(self, i)
	return self.ROpCode[i.OP];
end;
function opcodes.SET_OPCODE(self, i, o)
	i.OP = self.OpCode[o];
end;
function opcodes.GETARG_A(self, i)
	return i.A;
end;
function opcodes.SETARG_A(self, i, u)
	i.A = u;
end;
function opcodes.GETARG_B(self, i)
	return i.B;
end;
function opcodes.SETARG_B(self, i, b)
	i.B = b;
end;
function opcodes.GETARG_C(self, i)
	return i.C;
end;
function opcodes.SETARG_C(self, i, b)
	i.C = b;
end;
function opcodes.GETARG_Bx(self, i)
	return i.Bx;
end;
function opcodes.SETARG_Bx(self, i, b)
	i.Bx = b;
end;
function opcodes.GETARG_sBx(self, i)
	return i.Bx - self.MAXARG_sBx;
end;
function opcodes.SETARG_sBx(self, i, b)
	i.Bx = b + self.MAXARG_sBx;
end;
function opcodes.CREATE_ABC(self, o, a, b, c)
	return {
		OP = self.OpCode[o],
		A = a,
		B = b,
		C = c,
	};
end;
function opcodes.CREATE_ABx(self, o, a, bc)
	return { OP = self.OpCode[o], A = a, Bx = bc };
end;
function opcodes.CREATE_Inst(self, c)
	local o = c % 64;
	c = (c - o) / 64;
	local a = c % 256;
	c = (c - a) / 256;
	return self:CREATE_ABx(o, a, c);
end;
function opcodes.Instruction(self, i)
	if i.Bx then
		i.C = i.Bx % 512;
		i.B = (i.Bx - i.C) / 512;
	end;
	local I = i.A * 64 + i.OP;
	local c0 = I % 256;
	I = i.C * 64 + (I - c0) / 256;
	local c1 = I % 256;
	I = i.B * 128 + (I - c1) / 256;
	local c2 = I % 256;
	local c3 = (I - c2) / 256;
	return string.char(c0, c1, c2, c3);
end;
function opcodes.DecIns(self, i)
	if i.Bx then
		i.C = i.Bx % 512;
		i.B = (i.Bx - i.C) / 512;
	end;
	return {
		self.opnames[i.OP],
		i.A,
		i.B,
		i.C,
	};
end;
function opcodes.DecodeInst(self, x)
	local byte = string.byte;
	local i = {};
	local I = byte(x, 1);
	local op = I % 64;
	i.OP = op;
	I = byte(x, 2) * 4 + (I - op) / 64;
	local a = I % 256;
	i.A = a;
	I = byte(x, 3) * 4 + (I - a) / 256;
	local c = I % 512;
	i.C = c;
	i.B = byte(x, 4) * 2 + (I - c) / 512;
	local opmode = self.OpMode[tonumber(string.sub(self.opmodes[op + 1], 7, 7))];
	if opmode ~= "iABC" then
		i.Bx = i.B * 512 + i.C;
	end;
	return i;
end;
opcodes.BITRK = math.ldexp(1, opcodes.SIZE_B - 1);
function opcodes.ISK(self, x)
	return x >= self.BITRK;
end;
function opcodes.INDEXK(self, r)
	return x - self.BITRK;
end;
opcodes.MAXINDEXRK = opcodes.BITRK - 1;
function opcodes.RKASK(self, x)
	return x + self.BITRK;
end;
opcodes.NO_REG = opcodes.MAXARG_A;
opcodes.opnames = {};
opcodes.OpCode = {};
opcodes.ROpCode = {};
local i = 0;
for v in string.gmatch("MOVE LOADK LOADKX LOADBOOL LOADNIL GETUPVAL\nGETTABUP GETTABLE SETTABUP SETUPVAL SETTABLE\nNEWTABLE SELF ADD SUB MUL\nDIV MOD POW UNM NOT\nLEN CONCAT JMP EQ LT\nLE TEST TESTSET CALL TAILCALL\nRETURN FORLOOP FORPREP TFORCALL TFORLOOP SETLIST\nCLOSURE VARARG EXTRAARG IDIV BNOT BAND BOR BXOR SHL SHR\n", "%S+") do
	local n = "OP_" .. v;
	opcodes.opnames[i] = v;
	opcodes.OpCode[n] = i;
	opcodes.ROpCode[i] = n;
	i = i + 1;
end;
opcodes.NUM_OPCODES = i;
opcodes.OpArgMask = {
		OpArgN = 0,
		OpArgU = 1,
		OpArgR = 2,
		OpArgK = 3,
	};
function opcodes.getOpMode(self, m)
	return self.opmodes[self.OpCode[m]] % 4;
end;
function opcodes.getBMode(self, m)
	return math.floor(self.opmodes[self.OpCode[m]] / 16) % 4;
end;
function opcodes.getCMode(self, m)
	return math.floor(self.opmodes[self.OpCode[m]] / 4) % 4;
end;
function opcodes.testAMode(self, m)
	return math.floor(self.opmodes[self.OpCode[m]] / 64) % 2;
end;
function opcodes.testTMode(self, m)
	return math.floor(self.opmodes[self.OpCode[m]] / 128);
end;
opcodes.LFIELDS_PER_FLUSH = 50;
local function opmode(t, a, b, c, m)
	local opcodes = opcodes;
	return (((t * 128 + a * 64) + opcodes.OpArgMask[b] * 16) + opcodes.OpArgMask[c] * 4) + opcodes.OpMode[m];
end;
opcodes.opmodes = {
		opmode(0, 1, "OpArgK", "OpArgN", "iABx"),
		opmode(0, 1, "OpArgN", "OpArgN", "iABx"),
		opmode(0, 1, "OpArgU", "OpArgU", "iABC"),
		opmode(0, 1, "OpArgR", "OpArgN", "iABC"),
		opmode(0, 1, "OpArgU", "OpArgN", "iABC"),
		opmode(0, 1, "OpArgU", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgR", "OpArgK", "iABC"),
		opmode(0, 0, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 0, "OpArgU", "OpArgN", "iABC"),
		opmode(0, 0, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgU", "OpArgU", "iABC"),
		opmode(0, 1, "OpArgR", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgR", "OpArgN", "iABC"),
		opmode(0, 1, "OpArgR", "OpArgN", "iABC"),
		opmode(0, 1, "OpArgR", "OpArgN", "iABC"),
		opmode(0, 1, "OpArgR", "OpArgR", "iABC"),
		opmode(0, 0, "OpArgR", "OpArgN", "iAsBx"),
		opmode(1, 0, "OpArgK", "OpArgK", "iABC"),
		opmode(1, 0, "OpArgK", "OpArgK", "iABC"),
		opmode(1, 0, "OpArgK", "OpArgK", "iABC"),
		opmode(1, 1, "OpArgR", "OpArgU", "iABC"),
		opmode(1, 1, "OpArgR", "OpArgU", "iABC"),
		opmode(0, 1, "OpArgU", "OpArgU", "iABC"),
		opmode(0, 1, "OpArgU", "OpArgU", "iABC"),
		opmode(0, 0, "OpArgU", "OpArgN", "iABC"),
		opmode(0, 1, "OpArgR", "OpArgN", "iAsBx"),
		opmode(0, 1, "OpArgR", "OpArgN", "iAsBx"),
		opmode(1, 0, "OpArgN", "OpArgU", "iABC"),
		opmode(0, 1, "OpArgR", "OpArgN", "iAsBx"),
		opmode(0, 0, "OpArgU", "OpArgU", "iABC"),
		opmode(0, 1, "OpArgU", "OpArgN", "iABx"),
		opmode(0, 1, "OpArgU", "OpArgN", "iABC"),
		opmode(0, 0, "OpArgU", "OpArgU", "iAx"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgR", "OpArgN", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
		opmode(0, 1, "OpArgK", "OpArgK", "iABC"),
	};
opcodes.opmodes[0] = opmode(0, 1, "OpArgR", "OpArgN", "iABC");
return opcodes;