-- Context-only policy. One action per physical press; entering a menu while held
-- cannot assign a weapon or change a map floor.
local M={}
function M.new()
    local s={context=nil,left=true,right=true,assigned=false,status='Menu controls ready',actions=0}
    function s:step(i,context,assign,floor)
        if not i or not i.active or (context~='inventory' and context~='map') then
            self.context=nil;self.left=true;self.right=true;self.assigned=false;return
        end
        local l=i.leftStickClick==true;local r=i.rightStickClick==true
        if self.context~=context then
            self.context=context;self.left=l;self.right=r;self.assigned=l;return
        end
        if context=='map' then
            if l and not self.left and not r then
                local ok,why=floor('down');self.status=why or (ok and 'Map floor down' or 'Floor change unavailable');self.actions=self.actions+1
            elseif r and not self.right and not l then
                local ok,why=floor('up');self.status=why or (ok and 'Map floor up' or 'Floor change unavailable');self.actions=self.actions+1
            end
        else
            if not l then self.assigned=false end
            local axis=i.rightStickAxis or {x=0,y=0}
            if l and not self.assigned and not r and math.max(math.abs(axis.x),math.abs(axis.y))>=.75
                and math.abs(math.abs(axis.x)-math.abs(axis.y))>=.20 then
                local direction=math.abs(axis.x)>math.abs(axis.y) and (axis.x>0 and 'right' or 'left') or (axis.y>0 and 'up' or 'down')
                self.assigned=true -- consume before the native setter, including failures
                local ok,why=assign(direction);self.status=why or (ok and 'Shortcut assigned' or 'Shortcut assignment unavailable');self.actions=self.actions+1
            end
        end
        self.left=l;self.right=r
    end
    return s
end
return M
