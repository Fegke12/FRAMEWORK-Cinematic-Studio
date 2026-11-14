--[[
 HEAD FREECAM V5.1 — REFERENCE IMPLEMENTATION
 IMPORTANT: Rebuilt from features in chat, NOT original V5.1 source.
 Not Roblox Studio-tested. Use LocalScript (StarterPlayerScripts).
 F6 preview | F7 stop | F8 aspect | F9 camera style | F10 HUD
 WASD/Q/E movement | Shift boost | Ctrl slow | Mouse look (RMB)
 Z/X or wheel FOV | Gamepad sticks + triggers
]]
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("RunService")
local Lighting=game:GetService("Lighting")
local SG=game:GetService("StarterGui")
local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")
local cam=workspace.CurrentCamera
local env=_G
pcall(function() if getgenv then env=getgenv() end end)
pcall(function() if type(env.HeadFreecamStop)=="function" then env.HeadFreecamStop() end end)
local cfg={
 MoveSpeed=12, Boost=4, Slow=.20,
 MouseSensitivity=.14, StickSensitivity=115,
 PositionSmooth=13, RotationSmooth=13,
 FOV=70, MinFOV=20, MaxFOV=100, ZoomSmooth=6,
 Shakiness=.022, Swing=.03, WalkBob=.016,
 FocusRate=6, FocusMax=350
}
local formats={
 {"16:9",16/9},{"9:16",9/16},{"1:1",1},{"4:3",4/3}
}
local styles={"GIMBAL","HANDHELD","PHONE"}
local state={
 alive=true,preview=false,format=1,style=1,
 position=nil,renderPos=nil,pitch=0,yaw=0,
 fov=cfg.FOV,targetFov=cfg.FOV,
 showPanel=true,hideHUD=false,autoFocus=true,focus=30,
 color={brightness=0,contrast=0,saturation=0},
 saved={},connections={},hidden={},hiddenCore={},
 keys={},gamepadMove=Vector2.zero,gamepadLook=Vector2.zero,
 triggerUp=0,triggerDown=0,rightMouse=false,time=0
}
local function bind(event,callback)
 local c=event:Connect(callback)
 table.insert(state.connections,c)
 return c
end
local function new(class,props,parent)
 local x=Instance.new(class)
 for k,v in pairs(props) do x[k]=v end
 x.Parent=parent
 return x
end
local function alpha(rate,dt) return 1-math.exp(-rate*dt) end
local function fmt(x) return string.format("%.1f",x) end
local effects={}
local function cleanEffects()
 for _,o in ipairs(effects) do pcall(function()o:Destroy()end)end
 table.clear(effects)
end
local function newEffects()
 cleanEffects()
 table.insert(effects,new("ColorCorrectionEffect",{
 Name="HeadFreeCam_Color",Enabled=true,
 Brightness=state.color.brightness,
 Contrast=state.color.contrast,
 Saturation=state.color.saturation
 },Lighting))
 table.insert(effects,new("DepthOfFieldEffect",{
 Name="HeadFreeCam_DOF",Enabled=true,
 FocusDistance=state.focus,InFocusRadius=12,
 NearIntensity=.10,FarIntensity=.2
 },Lighting))
end
local crop=new("ScreenGui",{
 Name="HeadFreeCam_Crop",ResetOnSpawn=false,
 IgnoreGuiInset=true,DisplayOrder=9000,Enabled=false
},pg)
local masks={}
for _,key in ipairs({"Top","Bottom","Left","Right"}) do
 masks[key]=new("Frame",{
  BorderSizePixel=0,BackgroundColor3=Color3.new(0,0,0)
 },crop)
end
local function resizeCrop()
 local size=cam.ViewportSize
 local w,h=size.X,size.Y
 if w<1 or h<1 then return end
 local ratio=formats[state.format][2]
 local fw=math.min(w,h*ratio)
 local fh=fw/ratio
 local x,y=(w-fw)/2,(h-fh)/2
 masks.Top.Position=UDim2.fromOffset(0,0)
 masks.Top.Size=UDim2.fromOffset(w,y)
 masks.Bottom.Position=UDim2.fromOffset(0,y+fh)
 masks.Bottom.Size=UDim2.fromOffset(w,h-(y+fh))
 masks.Left.Position=UDim2.fromOffset(0,y)
 masks.Left.Size=UDim2.fromOffset(x,fh)
 masks.Right.Position=UDim2.fromOffset(x+fw,y)
 masks.Right.Size=UDim2.fromOffset(w-(x+fw),fh)
end
local gui=new("ScreenGui",{
 Name="HeadFreeCam_Menu",ResetOnSpawn=false,
 IgnoreGuiInset=true,DisplayOrder=9002
},pg)
local frame=new("Frame",{
 Position=UDim2.fromOffset(20,65),
 Size=UDim2.fromOffset(300,315),
 BackgroundColor3=Color3.fromRGB(18,23,31),
 BorderSizePixel=0
},gui)
new("UICorner",{CornerRadius=UDim.new(0,9)},frame)
local function label(txt,y)
 return new("TextLabel",{
  Position=UDim2.fromOffset(13,y),
  Size=UDim2.fromOffset(275,23),
  BackgroundTransparency=1,
  TextColor3=Color3.fromRGB(223,230,238),
  Text=txt,Font=Enum.Font.Gotham,TextSize=12,
  TextXAlignment=Enum.TextXAlignment.Left
 },frame)
end
local function button(txt,x,y,w,fn)
 local b=new("TextButton",{
  Position=UDim2.fromOffset(x,y),
  Size=UDim2.fromOffset(w,30),
  Text=txt,Font=Enum.Font.GothamMedium,TextSize=12,
  TextColor3=Color3.new(1,1,1),
  BackgroundColor3=Color3.fromRGB(44,66,89),
  BorderSizePixel=0
 },frame)
 new("UICorner",{CornerRadius=UDim.new(0,5)},b)
 bind(b.MouseButton1Click,fn)
 return b
end
local heading=label("HEAD FREECAM  •  V5.1 REFERENCE",10)
heading.Font=Enum.Font.GothamBold
local liveLabel=label("F6 to enter camera mode",43)
local togglePreview
button("CAMERA  F6",13,80,274,function()togglePreview(not state.preview)end)
local ratioBtn=button("16:9",13,119,133,function()
 state.format=state.format%#formats+1
 resizeCrop()
end)
local styleBtn=button("GIMBAL",154,119,133,function()
 state.style=state.style%#styles+1
end)
button("FOV −",13,158,133,function()
 state.targetFov=math.max(cfg.MinFOV,state.targetFov-5)
end)
button("FOV +",154,158,133,function()
 state.targetFov=math.min(cfg.MaxFOV,state.targetFov+5)
end)
button("FOCUS AUTO",13,197,274,function()
 state.autoFocus=not state.autoFocus
end)
label("WASD • Q/E • Shift/Ctrl • RMB look",239)
label("Gamepad sticks + triggers • F8 • F9",263)
label("F10 hide HUD  |  F7 full cleanup",286)
local focusParams=RaycastParams.new()
focusParams.FilterType=Enum.RaycastFilterType.Exclude
local function restoreHUD()
 for o,enabled in pairs(state.hidden) do
  if o.Parent then o.Enabled=enabled end
 end
 table.clear(state.hidden)
 for typ,enabled in pairs(state.hiddenCore) do
  pcall(function()SG:SetCoreGuiEnabled(typ,enabled)end)
 end
 table.clear(state.hiddenCore)
 state.hideHUD=false
end
local function toggleHUD()
 if state.hideHUD then restoreHUD();return end
 state.hideHUD=true
 for _,o in ipairs(pg:GetChildren()) do
  if o:IsA("ScreenGui") and o~=crop and o~=gui then
   state.hidden[o]=o.Enabled;o.Enabled=false
  end
 end
 for _,typ in ipairs(Enum.CoreGuiType:GetEnumItems()) do
  if typ~=Enum.CoreGuiType.All then
   local ok,enabled=pcall(function()return SG:GetCoreGuiEnabled(typ)end)
   if ok then
    state.hiddenCore[typ]=enabled
    pcall(function()SG:SetCoreGuiEnabled(typ,false)end)
   end
  end
 end
end
local function snapshotCamera()
 cam=workspace.CurrentCamera
 state.saved={
  camera=cam,kind=cam.CameraType,subject=cam.CameraSubject,
  fov=cam.FieldOfView,mouse=UIS.MouseBehavior
 }
end
local function restoreCamera()
 local current=workspace.CurrentCamera
 if not current then return end
 current.CameraType=state.saved.kind or Enum.CameraType.Custom
 local sub=state.saved.subject
 if sub and sub.Parent then current.CameraSubject=sub end
 current.FieldOfView=state.saved.fov or cfg.FOV
 UIS.MouseBehavior=state.saved.mouse or Enum.MouseBehavior.Default
 UIS.MouseIconEnabled=true
end
togglePreview=function(on)
 if on then
  snapshotCamera()
  state.position=cam.CFrame.Position
  state.renderPos=state.position
  local look=cam.CFrame.LookVector
  state.pitch=math.deg(math.asin(math.clamp(look.Y,-1,1)))
  state.yaw=math.deg(math.atan2(-look.X,-look.Z))
  state.fov=cam.FieldOfView
  state.targetFov=state.fov
  state.preview=true
  cam.CameraType=Enum.CameraType.Scriptable
  crop.Enabled=true;resizeCrop()
  newEffects()
 else
  if not state.preview then return end
  state.preview=false
  crop.Enabled=false
  restoreCamera()
  restoreHUD()
  cleanEffects()
 end
end
local function stop()
 if not state.alive then return end
 state.alive=false
 RS:UnbindFromRenderStep("HeadFreeCamV51Reference")
 if state.preview then togglePreview(false)end
 restoreHUD()
 cleanEffects()
 for _,c in ipairs(state.connections) do c:Disconnect()end
 gui:Destroy();crop:Destroy()
 if env.HeadFreecamStop==stop then env.HeadFreecamStop=nil end
end
env.HeadFreecamStop=stop
bind(UIS.InputBegan,function(i,processed)
 if UIS:GetFocusedTextBox() then return end
 if i.KeyCode==Enum.KeyCode.F7 then stop();return end
 if i.KeyCode==Enum.KeyCode.F6 then togglePreview(not state.preview);return end
 if i.KeyCode==Enum.KeyCode.F8 then
  state.format=state.format%#formats+1;resizeCrop();return
 end
 if i.KeyCode==Enum.KeyCode.F9 then
  state.style=state.style%#styles+1;return
 end
 if i.KeyCode==Enum.KeyCode.F10 then toggleHUD();return end
 if i.KeyCode==Enum.KeyCode.H then state.showPanel=not state.showPanel end
 if not state.preview or processed then return end
 if i.UserInputType==Enum.UserInputType.MouseButton2 then
  state.rightMouse=true
  UIS.MouseBehavior=Enum.MouseBehavior.LockCurrentPosition
 end
 state.keys[i.KeyCode]=true
end)
bind(UIS.InputEnded,function(i)
 state.keys[i.KeyCode]=nil
 if i.UserInputType==Enum.UserInputType.MouseButton2 then
  state.rightMouse=false
  UIS.MouseBehavior=Enum.MouseBehavior.Default
 end
end)
bind(UIS.InputChanged,function(i,processed)
 if not state.preview then return end
 if i.UserInputType==Enum.UserInputType.MouseMovement and state.rightMouse then
  state.yaw-=i.Delta.X*cfg.MouseSensitivity
  state.pitch=math.clamp(state.pitch-i.Delta.Y*cfg.MouseSensitivity,-88,88)
 elseif i.UserInputType==Enum.UserInputType.MouseWheel and not processed then
  state.targetFov=math.clamp(state.targetFov-i.Position.Z*3,
   cfg.MinFOV,cfg.MaxFOV)
 elseif i.KeyCode==Enum.KeyCode.Thumbstick1 then
  state.gamepadMove=Vector2.new(i.Position.X,i.Position.Y)
 elseif i.KeyCode==Enum.KeyCode.Thumbstick2 then
  state.gamepadLook=Vector2.new(i.Position.X,i.Position.Y)
 elseif i.KeyCode==Enum.KeyCode.ButtonR2 then
  state.triggerUp=i.Position.Z
 elseif i.KeyCode==Enum.KeyCode.ButtonL2 then
  state.triggerDown=i.Position.Z
 end
end)
local function pressed(k)
 return state.keys[k]==true
end
local focusClock=0
local sizeBefore=Vector2.zero
local function render(dt)
 if not state.alive then return end
 dt=math.min(dt,.05)
 if workspace.CurrentCamera~=cam then
  cam=workspace.CurrentCamera
  if state.preview then cam.CameraType=Enum.CameraType.Scriptable end
  resizeCrop()
 end
 if cam.ViewportSize~=sizeBefore then
  sizeBefore=cam.ViewportSize
  resizeCrop()
 end
 gui.Enabled=state.showPanel and not state.preview
 liveLabel.Text=(state.preview and "LIVE" or "EDITOR")..
  " | "..styles[state.style].." | FOV "..fmt(state.fov)
 styleBtn.Text=styles[state.style]
 ratioBtn.Text=formats[state.format][1]
 if not state.preview then return end
 state.time+=dt
 cam.CameraType=Enum.CameraType.Scriptable
 local sticks=state.gamepadLook
 if sticks.Magnitude>.15 then
  state.yaw-=sticks.X*cfg.StickSensitivity*dt
  state.pitch=math.clamp(state.pitch+sticks.Y*cfg.StickSensitivity*dt,-88,88)
 end
 local rot=CFrame.Angles(0,math.rad(state.yaw),0)*
  CFrame.Angles(math.rad(state.pitch),0,0)
 local localMove=Vector3.new(
  (pressed(Enum.KeyCode.D) and 1 or 0)-(pressed(Enum.KeyCode.A) and 1 or 0)
   +state.gamepadMove.X,
  (pressed(Enum.KeyCode.E) and 1 or 0)-(pressed(Enum.KeyCode.Q) and 1 or 0)
   +state.triggerUp-state.triggerDown,
  (pressed(Enum.KeyCode.S) and 1 or 0)-(pressed(Enum.KeyCode.W) and 1 or 0)
   -state.gamepadMove.Y
 )
 if localMove.Magnitude>1 then localMove=localMove.Unit end
 local speed=cfg.MoveSpeed
 if pressed(Enum.KeyCode.LeftShift) then speed*=cfg.Boost end
 if pressed(Enum.KeyCode.LeftControl) then speed*=cfg.Slow end
 state.position+=rot:VectorToWorldSpace(localMove)*speed*dt
 state.renderPos=state.renderPos:Lerp(state.position,
  alpha(cfg.PositionSmooth,dt))
 state.fov+=(state.targetFov-state.fov)*alpha(cfg.ZoomSmooth,dt)
 if pressed(Enum.KeyCode.Z) then
  state.targetFov=math.max(cfg.MinFOV,state.targetFov-dt*25)
 elseif pressed(Enum.KeyCode.X) then
  state.targetFov=math.min(cfg.MaxFOV,state.targetFov+dt*25)
 end
 local offset=Vector3.zero
 local sway=0
 if state.style==2 then
  offset=Vector3.new(
   math.sin(state.time*2.1)*cfg.Swing,
   math.sin(state.time*2.9)*cfg.Shakiness,
   0
  )
  sway=math.sin(state.time*1.7)*.0025
 elseif state.style==3 then
  offset=Vector3.new(
   math.sin(state.time*6)*cfg.WalkBob,
   math.cos(state.time*11)*cfg.WalkBob*.5,
   0
  )
  sway=math.sin(state.time*5)*.004
 end
 local cf=CFrame.new(state.renderPos)*rot*CFrame.new(offset)*
  CFrame.Angles(0,0,sway)
 cam.CFrame=cf
 cam.FieldOfView=state.fov
 if state.autoFocus then
  focusClock-=dt
  if focusClock<=0 then
   focusClock=.12
   local ignores={}
   if player.Character then table.insert(ignores,player.Character)end
   focusParams.FilterDescendantsInstances=ignores
   local hit=workspace:Raycast(cf.Position,cf.LookVector*cfg.FocusMax,focusParams)
   if hit then state.manualFocus=(hit.Position-cf.Position).Magnitude
   else state.manualFocus=cfg.FocusMax end
  end
 end
 state.focus+=(state.manualFocus-state.focus)*alpha(cfg.FocusRate,dt)
 cam.Focus=cf+cf.LookVector*math.max(state.focus,5)
 if effects[2] then effects[2].FocusDistance=state.focus end
end
RS:BindToRenderStep("HeadFreeCamV51Reference",
 Enum.RenderPriority.Camera.Value+3,render)
print("[Head FreeCam V5.1 reference] loaded — reconstructed, untested.")
