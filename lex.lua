local luac = require("luac");
local lex = {};
lex.RESERVED = "TK_AND and\nTK_BREAK break\nTK_DO do\nTK_ELSE else\nTK_ELSEIF elseif\nTK_END end\nTK_FALSE false\nTK_FOR for\nTK_FUNCTION function\nTK_GOTO goto\nTK_IF if\nTK_IN in\nTK_LOCAL local\nTK_NIL nil\nTK_NOT not\nTK_OR or\nTK_REPEAT repeat\nTK_RETURN return\nTK_THEN then\nTK_TRUE true\nTK_UNTIL until\nTK_WHILE while\nTK_CONCAT ..\nTK_DOTS ...\nTK_EQ ==\nTK_GE >=\nTK_LE <=\nTK_NE ~=\nTK_DBCOLON ::\nTK_IDIV //\nTK_SHR <<\nTK_SHL >>\nTK_NAME <name>\nTK_NUMBER <number>\nTK_STRING <string>\nTK_EOS <eof>";
lex.MAXSRC = 80;
lex.MAX_INT = 2147483645;
lex.LUA_QS = "\'%s\'";
lex.LUA_COMPAT_LSTR = 1;
function lex.init(self)
	local tokens, enums = {}, {};
	for v in string.gmatch(self.RESERVED, "[^\n]+") do
		local _, _, tok, str = string.find(v, "(%S+)%s+(%S+)");
		tokens[tok] = str;
		enums[str] = tok;
	end;
	self.tokens = tokens;
	self.enums = enums;
end;
lex:init();
function lex.chunkid(self, source, bufflen)
	local out;
	local first = string.sub(source, 1, 1);
	if first == "=" then
		out = string.sub(source, 2, bufflen);
	else
		if first == "@" then
			source = string.sub(source, 2);
			bufflen = bufflen - 7;
			local l = #source;
			out = "";
			if l > bufflen then
				source = string.sub(source, (1 + l) - bufflen);
				out = out .. "...";
			end;
			out = out .. source;
		else
			local len = string.find(source, "[\n\r]");
			len = len and len - 1 or #source;
			bufflen = bufflen - 16;
			if len > bufflen then
				len = bufflen;
			end;
			out = "[string \"";
			if len < #source then
				out = out .. (string.sub(source, 1, len) .. "...");
			else
				out = out .. source;
			end;
			out = out .. "\"]";
		end;
	end;
	return out;
end;
function lex.token2str(self, ls, token)
	if string.sub(token, 1, 3) ~= "TK_" then
		if string.find(token, "%c") then
			return string.format("char(%d)", string.byte(token));
		end;
		return token;
	else
		return self.tokens[token];
	end;
end;
function lex.lexerror(self, ls, msg, token)
	local function txtToken(ls, token)
		if token == "TK_NAME" or token == "TK_STRING" or token == "TK_NUMBER" then
			return ls.buff;
		else
			return self:token2str(ls, token);
		end;
	end;
	local buff = self:chunkid(ls.source, self.MAXSRC);
	local msg = string.format("%s:%d: %s", buff, ls.linenumber, msg);
	if token then
		msg = string.format("%s near " .. self.LUA_QS, msg, txtToken(ls, token));
	end;
	error(msg);
end;
function lex.syntaxerror(self, ls, msg)
	self:lexerror(ls, msg, ls.t.token);
end;
function lex.currIsNewline(self, ls)
	return ls.current == "\n" or ls.current == "\r";
end;
function lex.inclinenumber(self, ls)
	local old = ls.current;
	self:nextc(ls);
	if self:currIsNewline(ls) and ls.current ~= old then
		self:nextc(ls);
	end;
	ls.linenumber = ls.linenumber + 1;
	if ls.linenumber >= self.MAX_INT then
		self:syntaxerror(ls, "chunk has too many lines");
	end;
end;
function lex.setinput(self, L, ls, z, source)
	if not ls then
		ls = {};
	end;
	if not ls.lookahead then
		ls.lookahead = {};
	end;
	if not ls.t then
		ls.t = {};
	end;
	ls.decpoint = ".";
	ls.L = L;
	ls.lookahead.token = "TK_EOS";
	ls.z = z;
	ls.fs = nil;
	ls.linenumber = 1;
	ls.lastline = 1;
	ls.source = source;
	self:nextc(ls);
end;
function lex.check_next(self, ls, set)
	if not string.find(set, ls.current, 1, 1) then
		return false;
	end;
	self:save_and_next(ls);
	return true;
end;
function lex.next(self, ls)
	ls.lastline = ls.linenumber;
	if ls.lookahead.token ~= "TK_EOS" then
		ls.t.seminfo = ls.lookahead.seminfo;
		ls.t.token = ls.lookahead.token;
		ls.lookahead.token = "TK_EOS";
	else
		ls.t.token = self:llex(ls, ls.t);
	end;
end;
function lex.lookahead(self, ls)
	ls.lookahead.token = self:llex(ls, ls.lookahead);
end;
function lex.nextc(self, ls)
	local c = luac:zgetc(ls.z);
	ls.current = c;
	return c;
end;
function lex.save(self, ls, c)
	local buff = ls.buff;
	ls.buff = buff .. c;
end;
function lex.save_and_next(self, ls)
	self:save(ls, ls.current);
	return self:nextc(ls);
end;
function lex.str2d(self, s)
	local result = tonumber(s);
	if result then
		return result;
	end;
	if string.lower(string.sub(s, 1, 2)) == "0x" then
		result = tonumber(s, 16);
		if result then
			return result;
		end;
	end;
	return nil;
end;
function lex.buffreplace(self, ls, from, to)
	local result, buff = "", ls.buff;
	for p = 1, #buff, 1 do
		local c = string.sub(buff, p, p);
		if c == from then
			c = to;
		end;
		result = result .. c;
	end;
	ls.buff = result;
end;
function lex.trydecpoint(self, ls, Token)
	local old = ls.decpoint;
	self:buffreplace(ls, old, ls.decpoint);
	local seminfo = self:str2d(ls.buff);
	Token.seminfo = seminfo;
	if not seminfo then
		self:buffreplace(ls, ls.decpoint, ".");
		self:lexerror(ls, "malformed number", "TK_NUMBER");
	end;
end;
function lex.read_numeral(self, ls, Token)
	repeat
		self:save_and_next(ls);
	until string.find(ls.current, "%D") and ls.current ~= ".";
	if self:check_next(ls, "Ee") then
		self:check_next(ls, "+-");
	end;
	while string.find(ls.current, "^%w$") or ls.current == "_" do
		self:save_and_next(ls);
	end;
	self:buffreplace(ls, ".", ls.decpoint);
	local seminfo = self:str2d(ls.buff);
	Token.seminfo = seminfo;
	if not seminfo then
		self:trydecpoint(ls, Token);
	end;
end;
function lex.skip_sep(self, ls)
	local count = 0;
	local s = ls.current;
	self:save_and_next(ls);
	while ls.current == "=" do
		self:save_and_next(ls);
		count = count + 1;
	end;
	return ls.current == s and count or -count - 1;
end;
function lex.read_long_string(self, ls, Token, sep)
	local cont = 0;
	self:save_and_next(ls);
	if self:currIsNewline(ls) then
		self:inclinenumber(ls);
	end;
	while true do
		local c = ls.current;
		if c == "EOZ" then
			self:lexerror(ls, Token and "unfinished long string" or "unfinished long comment", "TK_EOS");
		elseif c == "[" then
			if self.LUA_COMPAT_LSTR then
				if self:skip_sep(ls) == sep then
					self:save_and_next(ls);
					cont = cont + 1;
					if self.LUA_COMPAT_LSTR == 1 then
						if sep == 0 then
							self:lexerror(ls, "nesting of [[...]] is deprecated", "[");
						end;
					end;
				end;
			end;
		elseif c == "]" then
			if self:skip_sep(ls) == sep then
				self:save_and_next(ls);
				if self.LUA_COMPAT_LSTR and self.LUA_COMPAT_LSTR == 2 then
					cont = cont - 1;
					if sep == 0 and cont >= 0 then
						break;
					end;
				end;
				break;
			end;
		elseif self:currIsNewline(ls) then
			self:save(ls, "\n");
			self:inclinenumber(ls);
			if not Token then
				ls.buff = "";
			end;
		else
			if Token then
				self:save_and_next(ls);
			else
				self:nextc(ls);
			end;
		end;
	end;
	if Token then
		local p = 3 + sep;
		Token.seminfo = string.sub(ls.buff, p, -p);
	end;
end;
function lex.read_string(self, ls, del, Token)
	self:save_and_next(ls);
	while ls.current ~= del do
		local c = ls.current;
		if c == "EOZ" then
			self:lexerror(ls, "unfinished string", "TK_EOS");
		elseif self:currIsNewline(ls) then
			self:lexerror(ls, "unfinished string", "TK_STRING");
		elseif c == "\\" then
			c = self:nextc(ls);
			if self:currIsNewline(ls) then
				self:save(ls, "\n");
				self:inclinenumber(ls);
			elseif c ~= "EOZ" then
				local i = string.find("abfnrtv", c, 1, 1);
				if i then
					self:save(ls, string.sub("\a\b\f\n\r\t\v", i, i));
					self:nextc(ls);
				elseif not string.find(c, "%d") then
					self:save_and_next(ls);
				else
					c, i = 0, 0;
					repeat
						c = 10 * c + ls.current;
						self:nextc(ls);
						i = i + 1;
					until i >= 3 or not string.find(ls.current, "%d");
					if c > 255 then
						self:lexerror(ls, "escape sequence too large", "TK_STRING");
					end;
					self:save(ls, string.char(c));
				end;
			end;
		else
			self:save_and_next(ls);
		end;
	end;
	self:save_and_next(ls);
	Token.seminfo = string.sub(ls.buff, 2, -2);
end;
function lex.llex(self, ls, Token)
	ls.buff = "";
	while true do
		local c = ls.current;
		if self:currIsNewline(ls) then
			self:inclinenumber(ls);
		elseif c == "-" then
			c = self:nextc(ls);
			if c ~= "-" then
				return "-";
			end;
			local sep = -1;
			if self:nextc(ls) == "[" then
				sep = self:skip_sep(ls);
				ls.buff = "";
			end;
			if sep >= 0 then
				self:read_long_string(ls, nil, sep);
				ls.buff = "";
			else
				while not self:currIsNewline(ls) and ls.current ~= "EOZ" do
					self:nextc(ls);
				end;
			end;
		elseif c == "[" then
			local sep = self:skip_sep(ls);
			if sep >= 0 then
				self:read_long_string(ls, Token, sep);
				return "TK_STRING";
			elseif sep == -1 then
				return "[";
			else
				self:lexerror(ls, "invalid long string delimiter", "TK_STRING");
			end;
		elseif c == "=" then
			c = self:nextc(ls);
			if c ~= "=" then
				return "=";
			else
				self:nextc(ls);
				return "TK_EQ";
			end;
		elseif c == "/" then
			c = self:nextc(ls);
			if c ~= "/" then
				return "/";
			else
				self:nextc(ls);
				return "TK_IDIV";
			end;
		elseif c == "<" then
			c = self:nextc(ls);
			if c == "<" then
				self:nextc(ls);
				return "TK_SHR";
			end;
			if c ~= "=" then
				return "<";
			else
				self:nextc(ls);
				return "TK_LE";
			end;
		elseif c == ">" then
			c = self:nextc(ls);
			if c == ">" then
				self:nextc(ls);
				return "TK_SHL";
			end;
			if c ~= "=" then
				return ">";
			else
				self:nextc(ls);
				return "TK_GE";
			end;
		elseif c == "~" then
			c = self:nextc(ls);
			if c ~= "=" then
				return "~";
			else
				self:nextc(ls);
				return "TK_NE";
			end;
		elseif c == ":" then
			c = self:nextc(ls);
			if c ~= ":" then
				return ":";
			else
				self:nextc(ls);
				return "TK_DBCOLON";
			end;
		elseif c == "\"" or c == "\'" then
			self:read_string(ls, c, Token);
			return "TK_STRING";
		elseif c == "." then
			c = self:save_and_next(ls);
			if self:check_next(ls, ".") then
				if self:check_next(ls, ".") then
					return "TK_DOTS";
				else
					return "TK_CONCAT";
				end;
			elseif not string.find(c, "%d") then
				return ".";
			else
				self:read_numeral(ls, Token);
				return "TK_NUMBER";
			end;
		elseif c == "EOZ" then
			return "TK_EOS";
		else
			if string.find(c, "%s") then
				self:nextc(ls);
			elseif string.find(c, "%d") then
				self:read_numeral(ls, Token);
				return "TK_NUMBER";
			elseif string.find(c, "[_%a]") then
				repeat
					c = self:save_and_next(ls);
				until c == "EOZ" or not string.find(c, "[_%w]");
				local ts = ls.buff;
				local tok = self.enums[ts];
				if tok then
					return tok;
				end;
				Token.seminfo = ts;
				return "TK_NAME";
			else
				self:nextc(ls);
				return c;
			end;
		end;
	end;
end;
return lex;