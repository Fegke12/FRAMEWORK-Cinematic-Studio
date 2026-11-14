--[[
 VEHICLE CAMERA RIG V3.1
 Chat-transcribed SOURCE REFERENCE for FRAMEWORK Cinematic Studio
 Important: this source is NOT runtime-tested during GitHub transfer.
 User's previous V3.1 worked in their vehicle place.
 
 F5 attach / F6 preview / F7 cleanup
 F8 aspect / F9 mode / F10 HUD / F11 grid
 M place camera on own vehicle with mouse
 T select another vehicle / C release target
 G show gimbal / H toggle panel / Z/X zoom / R reset
 
 Critical invariant:
 TRACKING MAY ROTATE THE CAMERA, NEVER MOVE IT TO THE TARGET.
 Camera world position = own seat CFrame * mountLocal + rig height.
]]
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("RunService")
local WS=game:GetService("Workspace")
local Lighting=game:GetService("Lighting")
local StarterGui=game:GetService("StarterGui")
local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")
local camera=WS.CurrentCamera
local env=_G
pcall(function()
 if type(getgenv)=="function" then env=getgenv() end
end)
for _,key in ipairs({"VehicleRigStop","HeadFreecamStop"}) do
 if type(env[key])=="function" then pcall(env[key]) end
end
for _,name in ipairs({"VehicleRigV1","VehicleRigV2","VehicleRigV3","VehicleRigV31"}) do
 pcall(function()RS:UnbindFromRenderStep(name)end)
end
local CFG={
 StartFOV=70,MinFOV=25,MaxFOV=100,
 ZoomRate=.62,ZoomTap=.07,ZoomHoldDelay=.2,ZoomSmoothTime=.36,
 SurfaceGap=.12,RigHeight=.55,MaxMountRadius=28,
 AngleStep=2,PositionStep=.10,
 RotationResponse=4.5,MaxRotationSpeed=55,
 PositionResponse=13,MaxPositionLag=.30,
 TargetResponse=5,TargetLead=.06,MaxTargetSpeed=120,
 MaxTargetDistance=650,MaxTargetHeightDifference=35,MaxTargetJump=40,
 FocusResponse=6,FocusMax=350,FocusStep=5,
 FrustumLength=3,RayDistance=1000
}
local formats={
 {name="16:9",ratio=16/9},{name="9:16",ratio=9/16},
 {name="1:1",ratio=1},{name="4:3",ratio=4/3}
}
local modes={"RIGID","GIMBAL","ACTIVE TRACK","WORLD LOCK"}
local S={
 running=true,preview=false,panelVisible=true,
 showRig=true,showGrid=false,cleanHUD=false,
 tool="NONE",dragging=false,
 format=1,mode=2,
 seat=nil,vehicle=nil,
 mountLocal=Vector3.new(0,1.6,0),normalLocal=Vector3.yAxis,
 pitch=0,yaw=0,roll=0,
 target=nil,targetSmoothed=nil,frameX=.5,frameY=.5,
 renderRotation=nil,renderPosition=nil,worldRotation=nil,
 currentFOV=CFG.StartFOV,
 autoFocus=true,dof=true,focusDistance=30,manualFocus=30,
 brightness=0,contrast=0,saturation=0,
 slots={},status="Сядь в машину и нажми F5"
}
local connections={}
local savedCamera={}
local hiddenGuis={}
local hiddenCore={}
local cropGui,panelGui,panel,rigFolder
local correction,dofEffect
local lastViewport=Vector2.zero
local cropW,cropH=1,1
local function connect(signal,fn)
 local c=signal:Connect(fn)
 table.insert(connections,c)
 return c
end
local function alpha(rate,dt)
 return 1-math.exp(-rate*dt)
end
local function clamp(v,a,b)
 return math.clamp(v,a,b)
end
local function finiteNumber(x)
 return x==x and x~=math.huge and x~=-math.huge and math.abs(x)<10000000
end
local function finiteVector(v)
 return finiteNumber(v.X) and finiteNumber(v.Y) and finiteNumber(v.Z)
end
local function make(class,props,parent)
 local object=Instance.new(class)
 for k,v in pairs(props) do object[k]=v end
 object.Parent=parent
 return object
end
local function rounded(object,radius)
 make("UICorner",{CornerRadius=UDim.new(0,radius or 6)},object)
end
local function currentSeat()
 local character=player.Character
 local hum=character and character:FindFirstChildOfClass("Humanoid")
 return hum and hum.SeatPart
end
local function validCarBounds(model)
 local ok,cf,size=pcall(function()return model:GetBoundingBox()end)
 if not ok or not finiteVector(cf.Position) or not finiteVector(size) then
  return false
 end
 return size.X<45 and size.Y<25 and size.Z<65 and size.Magnitude>2
end
local function hasVehicleSeat(model)
 return model:FindFirstChildWhichIsA("VehicleSeat",true)~=nil
  or model:FindFirstChildWhichIsA("Seat",true)~=nil
end
local function findCarModel(instance)
 local node=instance
 local best=nil
 while node and node~=WS do
  if node:IsA("Model") and hasVehicleSeat(node) and validCarBounds(node) then
   best=node
  end
  node=node.Parent
 end
 return best
end
local function mountAtWorldPoint(point,normal)
 local seat=S.seat
 if not seat or not seat.Parent or not finiteVector(point) or not finiteVector(normal) then
  return false
 end
 if (point-seat.Position).Magnitude>CFG.MaxMountRadius or normal.Magnitude<.01 then
  return false
 end
 S.mountLocal=seat.CFrame:PointToObjectSpace(point)
 S.normalLocal=seat.CFrame:VectorToObjectSpace(normal.Unit)
 return true
end
local function attachVehicle()
 local seat=currentSeat()
 if not seat then S.status="Сначала сядь за руль";return false end
 local vehicle=findCarModel(seat)
 if not vehicle then S.status="Модель автомобиля не найдена";return false end
 S.seat=seat
 S.vehicle=vehicle
 mountAtWorldPoint(seat.Position+seat.CFrame.UpVector*1.6,seat.CFrame.UpVector)
 S.renderPosition=nil
 S.renderRotation=nil
 S.worldRotation=nil
 S.target=nil
 S.targetSmoothed=nil
 S.status="Автомобиль привязан"
 return true
end
local function getMountFrame()
 local seat=S.seat
 if not seat or not seat.Parent then return nil end
 local cf=seat.CFrame
 if not finiteVector(cf.Position) then return nil end
 local normal=cf:VectorToWorldSpace(S.normalLocal)
 if normal.Magnitude<.01 then return nil end
 normal=normal.Unit
 local point=cf:PointToWorldSpace(S.mountLocal)+normal*CFG.SurfaceGap
 local forward=cf.LookVector
 forward=forward-normal*forward:Dot(normal)
 if forward.Magnitude<.01 then
  forward=cf.RightVector-normal*cf.RightVector:Dot(normal)
 end
 if forward.Magnitude<.01 then
  local fallback=math.abs(normal.Y)<.9 and Vector3.yAxis or Vector3.xAxis
  forward=fallback-normal*fallback:Dot(normal)
 end
 forward=forward.Unit
 local right=forward:Cross(normal).Unit
 return CFrame.fromMatrix(point,right,normal,-forward)
end
local function getCameraMountPosition(base)
 return base.Position+base.UpVector*CFG.RigHeight+base.LookVector*.12
end
local function trimRotation()
 return CFrame.Angles(math.rad(S.pitch),math.rad(S.yaw),math.rad(S.roll))
end
local mountRay=RaycastParams.new()
mountRay.FilterType=Enum.RaycastFilterType.Include
mountRay.IgnoreWater=true
local targetRay=RaycastParams.new()
targetRay.FilterType=Enum.RaycastFilterType.Exclude
targetRay.IgnoreWater=true
local function getMouseRay()
 camera=WS.CurrentCamera
 local point=UIS:GetMouseLocation()
 return camera:ViewportPointToRay(point.X,point.Y)
end
local function castMount()
 if not S.vehicle or not S.vehicle.Parent then return nil end
 mountRay.FilterDescendantsInstances={S.vehicle}
 local ray=getMouseRay()
 local hit=WS:Raycast(ray.Origin,ray.Direction*CFG.RayDistance,mountRay)
 if not hit or not hit.Instance:IsDescendantOf(S.vehicle) or not S.seat then
  return nil
 end
 if (hit.Position-S.seat.Position).Magnitude>CFG.MaxMountRadius then return nil end
 return hit
end
local function castTarget()
 local ignore={}
 if S.vehicle then table.insert(ignore,S.vehicle) end
 if player.Character then table.insert(ignore,player.Character) end
 if rigFolder then table.insert(ignore,rigFolder) end
 targetRay.FilterDescendantsInstances=ignore
 local ray=getMouseRay()
 return WS:Raycast(ray.Origin,ray.Direction*CFG.RayDistance,targetRay)
end
local function clearTarget()
 S.target=nil
 S.targetSmoothed=nil
 if S.mode==3 then S.mode=2 end
 S.status="Цель сброшена"
end
local function selectTarget(part)
 if not part then return false end
 if S.vehicle and part:IsDescendantOf(S.vehicle) then
  S.status="Выбери чужой автомобиль"
  return false
 end
 local model=findCarModel(part)
 if not model or model==S.vehicle then
  S.status="Не удалось выбрать автомобиль"
  return false
 end
 S.target=model
 S.targetSmoothed=nil
 S.mode=3
 S.worldRotation=nil
 -- Do NOT touch renderRotation or renderPosition!
 S.status="TRACK: "..model.Name
 return true
end
local function getTargetPosition(mountPosition)
 local target=S.target
 if not target or not target.Parent then return nil end
 local ok,cf,size=pcall(function()return target:GetBoundingBox()end)
 if not ok or not finiteVector(cf.Position) or not finiteVector(size) then return nil end
 if size.X>45 or size.Y>25 or size.Z>65 then return nil end
 local root=target.PrimaryPart
  or target:FindFirstChildWhichIsA("VehicleSeat",true)
  or target:FindFirstChildWhichIsA("BasePart",true)
 local velocity=root and root.AssemblyLinearVelocity or Vector3.zero
 if not finiteVector(velocity) then velocity=Vector3.zero end
 velocity=Vector3.new(velocity.X,0,velocity.Z)
 if velocity.Magnitude>CFG.MaxTargetSpeed then
  velocity=velocity.Unit*CFG.MaxTargetSpeed
 end
 local point=cf.Position+Vector3.yAxis*size.Y*.07+velocity*CFG.TargetLead
 if not finiteVector(point) then return nil end
 local difference=point-mountPosition
 if difference.Magnitude>CFG.MaxTargetDistance
  or math.abs(difference.Y)>CFG.MaxTargetHeightDifference then
  return nil
 end
 return point
end
local function fovToZoom(fov)
 return -math.log(math.tan(math.rad(fov)/2))
end
local function zoomToFov(value)
 return math.deg(2*math.atan(math.exp(-value)))
end
local minZoom=fovToZoom(CFG.MaxFOV)
local maxZoom=fovToZoom(CFG.MinFOV)
local currentZoom=fovToZoom(CFG.StartFOV)
local targetZoom=currentZoom
local zoomVelocity=0
local zoomInTime,zoomOutTime
local function smoothDamp(current,target,vel,time,dt)
 time=math.max(time,.001)
 local omega=2/time
 local x=omega*dt
 local e=1/(1+x+.48*x*x+.235*x*x*x)
 local difference=current-target
 local temp=(vel+omega*difference)*dt
 local newVelocity=(vel-omega*temp)*e
 local result=target+(difference+temp)*e
 if (target-current)*(target-result)<0 then result=target;newVelocity=0 end
 return result,newVelocity
end
local function zoomBy(value)
 targetZoom=clamp(targetZoom+value,minZoom,maxZoom)
end
local function updateZoom(dt)
 local now=os.clock()
 if zoomInTime and UIS:IsKeyDown(Enum.KeyCode.Z)
  and now-zoomInTime>CFG.ZoomHoldDelay then
  zoomBy(CFG.ZoomRate*dt)
 end
 if zoomOutTime and UIS:IsKeyDown(Enum.KeyCode.X)
  and now-zoomOutTime>CFG.ZoomHoldDelay then
  zoomBy(-CFG.ZoomRate*dt)
 end
 currentZoom,zoomVelocity=smoothDamp(currentZoom,targetZoom,zoomVelocity,CFG.ZoomSmoothTime,dt)
 S.currentFOV=zoomToFov(currentZoom)
 if S.preview then camera.FieldOfView=S.currentFOV end
end
local function limitedRotation(current,desired,response,maxDegrees,dt)
 if not current then return desired end
 local relative=current:ToObjectSpace(desired)
 local _,angle=relative:ToAxisAngle()
 local blend=alpha(response,dt)
 if math.abs(angle)>.00001 then
  blend=math.min(blend,math.rad(maxDegrees)*dt/math.abs(angle))
 end
 return current:Lerp(desired,clamp(blend,0,1))
end
cropGui=make("ScreenGui",{
 Name="VehicleRigV31_Crop",IgnoreGuiInset=true,ResetOnSpawn=false,
 DisplayOrder=9000,Enabled=false
},pg)
local masks={}
for _,name in ipairs({"Top","Bottom","Left","Right"}) do
 masks[name]=make("Frame",{
  Name=name,BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0
 },cropGui)
end
local cropBorder=make("Frame",{
 BackgroundTransparency=1,BorderSizePixel=0,Visible=false
},cropGui)
make("UIStroke",{
 Color=Color3.fromRGB(220,220,220),Transparency=.45,Thickness=1
},cropBorder)
local grid=make("Frame",{
 BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Visible=false
},cropBorder)
for i=1,2 do
 make("Frame",{
  Position=UDim2.fromScale(i/3,0),
  Size=UDim2.new(0,1,1,0),
  BackgroundColor3=Color3.new(1,1,1),
  BackgroundTransparency=.7,BorderSizePixel=0
 },grid)
 make("Frame",{
  Position=UDim2.fromScale(0,i/3),
  Size=UDim2.new(1,0,0,1),
  BackgroundColor3=Color3.new(1,1,1),
  BackgroundTransparency=.7,BorderSizePixel=0
 },grid)
end
local function updateCrop()
 local w=camera.ViewportSize.X
 local h=camera.ViewportSize.Y
 if w<=0 or h<=0 then return end
 local ratio=formats[S.format].ratio
 local fw=math.min(w,h*ratio)
 local fh=fw/ratio
 cropW,cropH=fw,fh
 local x=(w-fw)/2
 local y=(h-fh)/2
 masks.Top.Position=UDim2.fromOffset(0,0)
 masks.Top.Size=UDim2.fromOffset(w,y)
 masks.Bottom.Position=UDim2.fromOffset(0,y+fh)
 masks.Bottom.Size=UDim2.fromOffset(w,h-y-fh)
 masks.Left.Position=UDim2.fromOffset(0,y)
 masks.Left.Size=UDim2.fromOffset(x,fh)
 masks.Right.Position=UDim2.fromOffset(x+fw,y)
 masks.Right.Size=UDim2.fromOffset(w-x-fw,fh)
 cropBorder.Position=UDim2.fromOffset(x,y)
 cropBorder.Size=UDim2.fromOffset(fw,fh)
 cropBorder.Visible=S.showGrid
 grid.Visible=S.showGrid
 lastViewport=camera.ViewportSize
end
local function trackingRotation(pos,targetPos)
 local look=CFrame.lookAt(pos,targetPos,Vector3.yAxis)
 local viewportH=math.max(camera.ViewportSize.Y,1)
 local tangent=math.tan(math.rad(S.currentFOV)/2)
 local horizontal=math.atan((S.frameX-.5)*2*cropW/viewportH*tangent)
 local vertical=math.atan((S.frameY-.5)*2*cropH/viewportH*tangent)
 return (look*CFrame.Angles(vertical,horizontal,0)*trimRotation()).Rotation
end
rigFolder=make("Folder",{Name="VehicleRigV31_Local"},WS)
local rigParts={}
local function rigPart(name,size,color,shape,material)
 local p=make("Part",{
  Name=name,Size=size,Color=color,
  Shape=shape or Enum.PartType.Block,
  Material=material or Enum.Material.SmoothPlastic,
  Anchored=true,CanCollide=false,CanTouch=false,
  CanQuery=false,CastShadow=false
 },rigFolder)
 table.insert(rigParts,p)
 return p
end
local dark=Color3.fromRGB(27,31,37)
local metal=Color3.fromRGB(100,109,120)
local black=Color3.fromRGB(8,12,17)
local plate=rigPart("Mount Plate",Vector3.new(.55,.08,.55),dark)
local stem=rigPart("Mount Arm",Vector3.new(.1,.1,.4),metal)
local panMotor=rigPart("Pan Motor",Vector3.new(.3,.18,.3),dark,Enum.PartType.Cylinder)
local panArm=rigPart("Pan Arm",Vector3.new(.1,.1,.4),metal)
local tiltMotor=rigPart("Tilt Motor",Vector3.new(.23,.23,.23),dark,Enum.PartType.Ball)
local tiltArm=rigPart("Tilt Arm",Vector3.new(.1,.1,.4),metal)
local rollMotor=rigPart("Roll Motor",Vector3.new(.22,.22,.22),dark,Enum.PartType.Ball)
local cameraBody=rigPart("Camera Body",Vector3.new(.48,.34,.36),dark)
local topPlate=rigPart("Camera Top",Vector3.new(.42,.04,.27),metal)
local screen=rigPart("Camera Screen",Vector3.new(.36,.24,.035),black)
local lens=rigPart("Lens",Vector3.new(.29,.34,.29),black,Enum.PartType.Cylinder)
local lensRing=rigPart("Lens Ring",Vector3.new(.32,.035,.32),metal,Enum.PartType.Cylinder)
local lensGlass=rigPart("Lens Glass",Vector3.new(.23,.025,.23),
 Color3.fromRGB(20,55,74),Enum.PartType.Cylinder,Enum.Material.Glass)
local tracker=rigPart("Tracking Module",Vector3.new(.20,.14,.16),black)
local trackerLED=rigPart("Tracking LED",Vector3.new(.06,.06,.06),
 Color3.fromRGB(55,240,125),Enum.PartType.Ball,Enum.Material.Neon)
local axes={
 rigPart("X Axis",Vector3.new(.035,.035,1),Color3.fromRGB(255,60,60)),
 rigPart("Y Axis",Vector3.new(.035,.035,1),Color3.fromRGB(60,255,100)),
 rigPart("Z Axis",Vector3.new(.035,.035,1),Color3.fromRGB(60,145,255))
}
local frustum={}
for i=1,4 do
 frustum[i]=rigPart("Frustum "..i,Vector3.new(.02,.02,1),
  Color3.fromRGB(255,216,65),nil,Enum.Material.Neon)
end
local cursor=rigPart("Mount Cursor",Vector3.new(.15,.15,.15),
 Color3.fromRGB(255,195,55),Enum.PartType.Ball,Enum.Material.Neon)
local targetBeam=rigPart("Target Beam",Vector3.new(.025,.025,1),
 Color3.fromRGB(60,255,120),nil,Enum.Material.Neon)
local highlight=make("Highlight",{
 FillColor=Color3.fromRGB(60,255,120),
 FillTransparency=.9,
 OutlineColor=Color3.fromRGB(60,255,120),
 OutlineTransparency=0,Enabled=false,
 DepthMode=Enum.HighlightDepthMode.Occluded
},rigFolder)
local function setRod(p,a,b,width)
 local difference=b-a
 if difference.Magnitude<.001 then return end
 p.Size=Vector3.new(width,width,difference.Magnitude)
 p.CFrame=CFrame.lookAt((a+b)/2,b)
end
local function hideRig()
 for _,p in ipairs(rigParts) do p.Transparency=1 end
 highlight.Enabled=false
end
local function renderRig(base,headCF,targetPos)
 local visible=S.showRig and not S.preview
 if not visible or not base then hideRig();return end
 for _,p in ipairs(rigParts) do p.Transparency=0 end
 lensGlass.Transparency=.2
 cursor.Transparency=1
 targetBeam.Transparency=1
 local origin=base.Position
 local up=base.UpVector
 local right=base.RightVector
 plate.CFrame=base*CFrame.new(0,-.05,0)
 local panPos=origin+up*.30
 setRod(stem,origin,panPos,.13)
 panMotor.CFrame=CFrame.new(panPos)*base.Rotation
 local joint1=panPos+up*.13+right*.34
 setRod(panArm,panPos,joint1,.10)
 tiltMotor.Position=joint1
 local headPos=headCF.Position
 local joint2=headPos+headCF.RightVector*.32
 setRod(tiltArm,joint1,joint2,.10)
 rollMotor.Position=joint2
 cameraBody.CFrame=headCF*CFrame.new(0,0,.08)
 topPlate.CFrame=headCF*CFrame.new(0,.19,.09)
 screen.CFrame=headCF*CFrame.new(0,0,.28)
 local lensRotation=CFrame.Angles(math.rad(-90),0,0)
 lens.CFrame=headCF*CFrame.new(0,0,-.29)*lensRotation
 lensRing.CFrame=headCF*CFrame.new(0,0,-.44)*lensRotation
 lensGlass.CFrame=headCF*CFrame.new(0,0,-.46)*lensRotation
 tracker.CFrame=headCF*CFrame.new(0,.27,.07)
 trackerLED.CFrame=headCF*CFrame.new(0,.28,-.025)
 trackerLED.Color=S.target and Color3.fromRGB(60,255,120)
  or Color3.fromRGB(255,165,45)
 setRod(axes[1],origin,origin+base.RightVector*.9,.035)
 setRod(axes[2],origin,origin+base.UpVector*.9,.035)
 setRod(axes[3],origin,origin+base.LookVector*.9,.035)
 local d=CFG.FrustumLength
 local h=math.max(camera.ViewportSize.Y,1)
 local tangent=math.tan(math.rad(S.currentFOV)/2)
 local halfH=tangent*d*cropH/h
 local halfW=tangent*d*cropW/h
 local index=1
 for _,x in ipairs({-1,1}) do
  for _,y in ipairs({-1,1}) do
   local corner=headCF*Vector3.new(halfW*x,halfH*y,-d)
   setRod(frustum[index],headPos,corner,.02)
   index+=1
  end
 end
 if targetPos then
  local difference=targetPos-headPos
  if difference.Magnitude>.01 then
   setRod(targetBeam,headPos,headPos+difference.Unit*
    math.min(difference.Magnitude,12),.025)
   targetBeam.Transparency=.15
  end
 end
 highlight.Adornee=S.target and S.target.Parent and S.target or nil
 highlight.Enabled=highlight.Adornee~=nil
end
local focusRay=RaycastParams.new()
focusRay.FilterType=Enum.RaycastFilterType.Exclude
focusRay.IgnoreWater=true
local focusTimer=0
local function createEffects()
 if correction then correction:Destroy() end
 if dofEffect then dofEffect:Destroy() end
 correction=make("ColorCorrectionEffect",{
  Name="VehicleRigV31_Color",Enabled=true,
  Brightness=S.brightness,Contrast=S.contrast,Saturation=S.saturation
 },Lighting)
 dofEffect=make("DepthOfFieldEffect",{
  Name="VehicleRigV31_DOF",Enabled=S.dof,
  FocusDistance=S.focusDistance,InFocusRadius=12,
  NearIntensity=.1,FarIntensity=.22
 },Lighting)
end
local function removeEffects()
 if correction then correction:Destroy();correction=nil end
 if dofEffect then dofEffect:Destroy();dofEffect=nil end
end
local function applyColor()
 if correction then
  correction.Brightness=S.brightness
  correction.Contrast=S.contrast
  correction.Saturation=S.saturation
 end
end
local function updateFocus(dt,tracked)
 if tracked and S.mode==3 and S.autoFocus then
  S.manualFocus=(tracked-camera.CFrame.Position).Magnitude
 elseif S.autoFocus then
  focusTimer-=dt
  if focusTimer<=0 then
   focusTimer=.15
   local ignore={rigFolder}
   if S.vehicle then table.insert(ignore,S.vehicle)end
   if player.Character then table.insert(ignore,player.Character)end
   focusRay.FilterDescendantsInstances=ignore
   local hit=WS:Raycast(camera.CFrame.Position,
    camera.CFrame.LookVector*CFG.FocusMax,focusRay)
   S.manualFocus=hit and (hit.Position-camera.CFrame.Position).Magnitude
    or CFG.FocusMax
  end
 end
 S.focusDistance+=(S.manualFocus-S.focusDistance)*
  alpha(CFG.FocusResponse,dt)
 if dofEffect then
  dofEffect.Enabled=S.dof
  dofEffect.FocusDistance=S.focusDistance
 end
 camera.Focus=camera.CFrame+camera.CFrame.LookVector*
  math.max(S.focusDistance,5)
end
local hiddenGuis={}
local hiddenCore={}
local function restoreHUD()
 for gui,enabled in pairs(hiddenGuis) do
  if gui.Parent then gui.Enabled=enabled end
 end
 hiddenGuis={}
 for kind,enabled in pairs(hiddenCore) do
  pcall(function()StarterGui:SetCoreGuiEnabled(kind,enabled)end)
 end
 hiddenCore={}
 pcall(function()StarterGui:SetCore("TopbarEnabled",true)end)
 S.cleanHUD=false
end
local function hideHUD()
 if S.cleanHUD then return end
 S.cleanHUD=true
 for _,gui in ipairs(pg:GetChildren()) do
  if gui:IsA("ScreenGui") and gui~=cropGui and gui~=panelGui then
   hiddenGuis[gui]=gui.Enabled
   gui.Enabled=false
  end
 end
 for _,kind in ipairs(Enum.CoreGuiType:GetEnumItems()) do
  if kind~=Enum.CoreGuiType.All then
   local ok,enabled=pcall(function()return StarterGui:GetCoreGuiEnabled(kind)end)
   if ok then
    hiddenCore[kind]=enabled
    pcall(function()StarterGui:SetCoreGuiEnabled(kind,false)end)
   end
  end
 end
 pcall(function()StarterGui:SetCore("TopbarEnabled",false)end)
end
local function toggleHUD()
 if S.cleanHUD then restoreHUD() else hideHUD() end
end
panelGui=make("ScreenGui",{
 Name="VehicleRigV31_Panel",IgnoreGuiInset=true,ResetOnSpawn=false,
 DisplayOrder=9001
},pg)
panel=make("ScrollingFrame",{
 Position=UDim2.fromOffset(15,60),Size=UDim2.fromOffset(390,540),
 CanvasSize=UDim2.fromOffset(0,790),ScrollBarThickness=4,
 BackgroundColor3=Color3.fromRGB(17,21,28),
 BackgroundTransparency=.05,BorderSizePixel=0
},panelGui)
rounded(panel,9)
local function label(str,x,y,w,h)
 return make("TextLabel",{
  Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h or 27),
  BackgroundTransparency=1,Text=str,
  TextColor3=Color3.fromRGB(225,230,240),
  TextSize=12,Font=Enum.Font.Gotham,
  TextXAlignment=Enum.TextXAlignment.Left
 },panel)
end
local function button(str,x,y,w,callback)
 local b=make("TextButton",{
  Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,28),
  BackgroundColor3=Color3.fromRGB(44,61,82),BorderSizePixel=0,
  TextColor3=Color3.new(1,1,1),Text=str,
  TextSize=12,Font=Enum.Font.GothamMedium
 },panel)
 rounded(b,5)
 connect(b.MouseButton1Click,callback)
 return b
end
local refreshUI=function()end
local setPreview
local title=label("VEHICLE CAMERA RIG V3.1",12,8,360,27)
title.Font=Enum.Font.GothamBold
title.TextSize=14
local statusLabel=label("",12,36,360,35)
statusLabel.TextWrapped=true
statusLabel.TextColor3=Color3.fromRGB(145,195,235)
button("ATTACH",12,79,115,function()attachVehicle();refreshUI()end)
local placeBtn=button("PLACE",135,79,115,function()
 if S.preview then return end
 S.tool=S.tool=="PLACE" and "NONE" or "PLACE"
 refreshUI()
end)
local targetBtn=button("TARGET",258,79,115,function()
 S.tool=S.tool=="TARGET" and "NONE" or "TARGET"
 refreshUI()
end)
local previewBtn=button("CAMERA PREVIEW",12,115,361,function()
 setPreview(not S.preview)
end)
local modeBtn=button("GIMBAL",12,152,175,function()
 S.mode=S.mode%#modes+1
 S.worldRotation=S.mode==4 and S.renderRotation or nil
 refreshUI()
end)
local formatBtn=button("16:9",198,152,175,function()
 S.format=S.format%#formats+1
 updateCrop()
 refreshUI()
end)
label("ACTIVE TRACK: TARGET POSITION",12,193,330)
local frameButtons={}
for yi=1,3 do
 for xi=1,3 do
  local xs={.32,.5,.68}
  local ys={.35,.5,.65}
  local bx,by=xs[xi],ys[yi]
  local b=button("·",12+(xi-1)*49,224+(yi-1)*35,42,function()
   S.frameX=bx;S.frameY=by;refreshUI()
  end)
  table.insert(frameButtons,{button=b,x=bx,y=by})
 end
end
local compositionInfo=label("Выбор композиции:\nлевая / центр / правая треть",175,233,195,75)
compositionInfo.TextWrapped=true
local function valueRow(name,y,minus,plus)
 label(name,12,y,155)
 button("-",175,y,38,minus)
 local value=label("",220,y,90)
 value.TextXAlignment=Enum.TextXAlignment.Center
 button("+",327,y,38,plus)
 return value
end
local pitchValue=valueRow("Pitch",345,function()
 S.pitch-=CFG.AngleStep;refreshUI()
end,function()
 S.pitch+=CFG.AngleStep;refreshUI()
end)
local yawValue=valueRow("Yaw",381,function()
 S.yaw-=CFG.AngleStep;refreshUI()
end,function()
 S.yaw+=CFG.AngleStep;refreshUI()
end)
local rollValue=valueRow("Roll",417,function()
 S.roll-=CFG.AngleStep;refreshUI()
end,function()
 S.roll+=CFG.AngleStep;refreshUI()
end)
local fovValue=valueRow("Field of View",453,function()
 zoomBy(.09);refreshUI()
end,function()
 zoomBy(-.09);refreshUI()
end)
local speedValue=valueRow("Tracking Speed",489,function()
 CFG.MaxRotationSpeed=clamp(CFG.MaxRotationSpeed-5,10,180);refreshUI()
end,function()
 CFG.MaxRotationSpeed=clamp(CFG.MaxRotationSpeed+5,10,180);refreshUI()
end)
local leadValue=valueRow("Prediction",525,function()
 CFG.TargetLead=clamp(CFG.TargetLead-.02,0,.3);refreshUI()
end,function()
 CFG.TargetLead=clamp(CFG.TargetLead+.02,0,.3);refreshUI()
end)
local focusValue=valueRow("Manual Focus",561,function()
 S.autoFocus=false
 S.manualFocus=clamp(S.manualFocus-CFG.FocusStep,2,CFG.FocusMax)
 refreshUI()
end,function()
 S.autoFocus=false
 S.manualFocus=clamp(S.manualFocus+CFG.FocusStep,2,CFG.FocusMax)
 refreshUI()
end)
local brightValue=valueRow("Brightness",597,function()
 S.brightness=clamp(S.brightness-.025,-.25,.25)
 applyColor();refreshUI()
end,function()
 S.brightness=clamp(S.brightness+.025,-.25,.25)
 applyColor();refreshUI()
end)
local contrastValue=valueRow("Contrast",633,function()
 S.contrast=clamp(S.contrast-.05,-.5,.5)
 applyColor();refreshUI()
end,function()
 S.contrast=clamp(S.contrast+.05,-.5,.5)
 applyColor();refreshUI()
end)
local saturationValue=valueRow("Saturation",669,function()
 S.saturation=clamp(S.saturation-.05,-.75,.75)
 applyColor();refreshUI()
end,function()
 S.saturation=clamp(S.saturation+.05,-.75,.75)
 applyColor();refreshUI()
end)
local dofBtn=button("DOF ON",12,708,175,function()
 S.dof=not S.dof;refreshUI()
end)
local focusBtn=button("AUTOFOCUS",198,708,175,function()
 S.autoFocus=not S.autoFocus
 if not S.autoFocus then S.manualFocus=S.focusDistance end
 refreshUI()
end)
local function saveSlot(i)
 if not S.seat then S.status="Сначала закрепи камеру";return end
 S.slots[i]={
  seat=S.seat,mount=S.mountLocal,normal=S.normalLocal,
  pitch=S.pitch,yaw=S.yaw,roll=S.roll,
  mode=S.mode,format=S.format,zoom=targetZoom,
  frameX=S.frameX,frameY=S.frameY
 }
 S.status="Пресет "..i.." сохранён"
end
local function loadSlot(i)
 local slot=S.slots[i]
 if not slot or slot.seat~=S.seat then
  S.status="Пресет недоступен для этой машины";return
 end
 S.mountLocal=slot.mount;S.normalLocal=slot.normal
 S.pitch=slot.pitch;S.yaw=slot.yaw;S.roll=slot.roll
 S.mode=slot.mode;S.format=slot.format
 targetZoom=slot.zoom
 S.frameX=slot.frameX;S.frameY=slot.frameY
 S.worldRotation=S.mode==4 and S.renderRotation or nil
 updateCrop()
 S.status="Пресет "..i.." загружен"
end
for i=1,3 do
 local slot=i
 local x=12+(i-1)*122
 button("SAVE "..i,x,747,56,function()
  saveSlot(slot);refreshUI()
 end)
 button("LOAD",x+61,747,56,function()
  loadSlot(slot);refreshUI()
 end)
end
refreshUI=function()
 statusLabel.Text=S.status
 modeBtn.Text=modes[S.mode]
 formatBtn.Text=formats[S.format].name
 placeBtn.Text=S.tool=="PLACE" and "PLACE: ON" or "PLACE"
 targetBtn.Text=S.tool=="TARGET" and "PICK TARGET" or "TARGET"
 previewBtn.Text=S.preview and "BACK TO EDITOR" or "CAMERA PREVIEW"
 pitchValue.Text=string.format("%.0f°",S.pitch)
 yawValue.Text=string.format("%.0f°",S.yaw)
 rollValue.Text=string.format("%.0f°",S.roll)
 fovValue.Text=string.format("%.1f°",S.currentFOV)
 speedValue.Text=string.format("%.0f°/s",CFG.MaxRotationSpeed)
 leadValue.Text=string.format("%.2f",CFG.TargetLead)
 focusValue.Text=string.format("%.1f",S.focusDistance)
 brightValue.Text=string.format("%+.3f",S.brightness)
 contrastValue.Text=string.format("%+.2f",S.contrast)
 saturationValue.Text=string.format("%+.2f",S.saturation)
 dofBtn.Text=S.dof and "DOF ON" or "DOF OFF"
 focusBtn.Text=S.autoFocus and "AUTOFOCUS" or "MANUAL FOCUS"
 for _,entry in ipairs(frameButtons) do
  local selected=math.abs(entry.x-S.frameX)<.02 and math.abs(entry.y-S.frameY)<.02
  entry.button.BackgroundColor3=selected
   and Color3.fromRGB(48,128,205) or Color3.fromRGB(44,61,82)
  entry.button.Text=selected and "●" or "·"
 end
end
local function updatePanel()
 panelGui.Enabled=S.panelVisible
end
local function restoreCamera()
 camera=WS.CurrentCamera
 if not camera then return end
 camera.CameraType=savedCamera.Type or Enum.CameraType.Custom
 if savedCamera.Subject and savedCamera.Subject.Parent then
  camera.CameraSubject=savedCamera.Subject
 else
  local character=player.Character
  local hum=character and character:FindFirstChildOfClass("Humanoid")
  if hum then camera.CameraSubject=hum end
 end
 camera.FieldOfView=savedCamera.FOV or CFG.StartFOV
 UIS.MouseBehavior=savedCamera.MouseBehavior or Enum.MouseBehavior.Default
end
setPreview=function(enabled)
 if enabled then
  if not S.seat or not S.seat.Parent then
   if not attachVehicle() then refreshUI();return end
  end
  camera=WS.CurrentCamera
  savedCamera.Type=camera.CameraType
  savedCamera.Subject=camera.CameraSubject
  savedCamera.FOV=camera.FieldOfView
  savedCamera.MouseBehavior=UIS.MouseBehavior
  if savedCamera.Type==Enum.CameraType.Scriptable then
   savedCamera.Type=Enum.CameraType.Custom
  end
  local base=getMountFrame()
  if base and not S.renderRotation then
   S.renderRotation=(base*trimRotation()).Rotation
  end
  S.preview=true
  S.tool="NONE";S.dragging=false
  camera.CameraType=Enum.CameraType.Scriptable
  createEffects()
  cropGui.Enabled=true
  updateCrop()
  S.panelVisible=false
  updatePanel()
  S.status="CAMERA LIVE"
 else
  if not S.preview then return end
  S.preview=false
  cropGui.Enabled=false
  restoreCamera()
  removeEffects()
  restoreHUD()
  S.panelVisible=true
  updatePanel()
  S.status="Режим настройки"
 end
 refreshUI()
end
local uiTimer=0
local hudTimer=0
local function render(dt)
 if not S.running then return end
 dt=math.min(dt,.05)
 local newCamera=WS.CurrentCamera
 if newCamera~=camera then
  camera=newCamera;lastViewport=Vector2.zero
  if S.preview then camera.CameraType=Enum.CameraType.Scriptable end
 end
 if camera.ViewportSize~=lastViewport then updateCrop() end
 if S.dragging and S.tool=="PLACE" and not S.preview then
  local hit=castMount()
  if hit then mountAtWorldPoint(hit.Position,hit.Normal) end
 end
 local base=getMountFrame()
 if not base then
  hideRig()
  if S.preview then setPreview(false) end
  return
 end
 -- CAMERA POSITION: OWN VEHICLE ONLY
 -- DO NOT ADD target.Position or target velocity to this section.
 local mountPosition=getCameraMountPosition(base)
 if not finiteVector(mountPosition) then return end
 if not S.renderPosition then
  S.renderPosition=mountPosition
 else
  S.renderPosition=S.renderPosition:Lerp(mountPosition,
   alpha(CFG.PositionResponse,dt))
  local offset=S.renderPosition-mountPosition
  if offset.Magnitude>CFG.MaxPositionLag then
   S.renderPosition=mountPosition+offset.Unit*CFG.MaxPositionLag
  end
 end
 local tracked=nil
 if S.target and not S.target.Parent then clearTarget() end
 if S.mode==3 and S.target then
  local raw=getTargetPosition(S.renderPosition)
  if raw then
   if not S.targetSmoothed then
    S.targetSmoothed=raw
   elseif (raw-S.targetSmoothed).Magnitude<CFG.MaxTargetJump then
    S.targetSmoothed=S.targetSmoothed:Lerp(raw,
     alpha(CFG.TargetResponse,dt))
   end
   tracked=S.targetSmoothed
  else
   S.targetSmoothed=nil
  end
 end
 local rigidRotation=(base*trimRotation()).Rotation
 local desiredRotation=rigidRotation
 if S.mode==2 or (S.mode==3 and not tracked) then
  local direction=(base*trimRotation()).LookVector
  if math.abs(direction:Dot(Vector3.yAxis))<.98 then
   desiredRotation=(CFrame.lookAt(
    S.renderPosition,S.renderPosition+direction,Vector3.yAxis)
    *CFrame.Angles(0,0,math.rad(S.roll))).Rotation
  else
   desiredRotation=S.renderRotation or rigidRotation
  end
 elseif S.mode==3 and tracked then
  if (tracked-S.renderPosition).Magnitude>.1 then
   desiredRotation=trackingRotation(S.renderPosition,tracked)
  end
 elseif S.mode==4 then
  if not S.worldRotation then
   S.worldRotation=S.renderRotation or rigidRotation
  end
  desiredRotation=S.worldRotation
 end
 if S.mode==1 then
  S.renderRotation=desiredRotation
 else
  S.renderRotation=limitedRotation(
   S.renderRotation,desiredRotation,CFG.RotationResponse,
   CFG.MaxRotationSpeed,dt
  )
 end
 local finalCF=CFrame.new(S.renderPosition)*S.renderRotation
 updateZoom(dt)
 if S.preview then
  camera.CameraType=Enum.CameraType.Scriptable
  camera.CFrame=finalCF
  updateFocus(dt,tracked)
 end
 renderRig(base,finalCF,tracked)
 if not S.preview and S.showRig and S.tool=="PLACE" then
  local hit=castMount()
  if hit then
   cursor.Position=hit.Position+hit.Normal*.08
   cursor.Transparency=0
  end
 end
 if S.cleanHUD then
  hudTimer+=dt
  if hudTimer>=.35 then
   hudTimer=0
   for _,gui in ipairs(pg:GetChildren()) do
    if gui:IsA("ScreenGui") and gui~=cropGui and gui~=panelGui then
     if hiddenGuis[gui]==nil then hiddenGuis[gui]=gui.Enabled end
     gui.Enabled=false
    end
   end
  end
 end
 uiTimer+=dt
 if uiTimer>=.2 then uiTimer=0;refreshUI() end
end
local function stop()
 if not S.running then return end
 S.running=false
 RS:UnbindFromRenderStep("VehicleRigV31")
 if S.preview then setPreview(false) end
 restoreHUD()
 removeEffects()
 for _,c in ipairs(connections) do c:Disconnect() end
 rigFolder:Destroy()
 cropGui:Destroy()
 panelGui:Destroy()
 if env.VehicleRigStop==stop then env.VehicleRigStop=nil end
end
env.VehicleRigStop=stop
local function pointerOverPanel()
 if not panelGui.Enabled then return false end
 local p=UIS:GetMouseLocation()
 local a=panel.AbsolutePosition
 local size=panel.AbsoluteSize
 return p.X>=a.X and p.X<=a.X+size.X
  and p.Y>=a.Y and p.Y<=a.Y+size.Y
end
connect(UIS.InputBegan,function(input,processed)
 if UIS:GetFocusedTextBox() then return end
 local k=input.KeyCode
 if k==Enum.KeyCode.F7 then stop();return end
 if k==Enum.KeyCode.F5 then attachVehicle();refreshUI();return end
 if k==Enum.KeyCode.F6 then setPreview(not S.preview);return end
 if k==Enum.KeyCode.F8 then
  S.format=S.format%#formats+1;updateCrop();refreshUI();return
 end
 if k==Enum.KeyCode.F9 then
  S.mode=S.mode%#modes+1
  S.worldRotation=S.mode==4 and S.renderRotation or nil
  refreshUI();return
 end
 if k==Enum.KeyCode.F10 then toggleHUD();return end
 if k==Enum.KeyCode.F11 then
  S.showGrid=not S.showGrid;updateCrop();return
 end
 if k==Enum.KeyCode.G then S.showRig=not S.showRig;return end
 if k==Enum.KeyCode.H then
  S.panelVisible=not S.panelVisible
  updatePanel();return
 end
 if k==Enum.KeyCode.C then clearTarget();refreshUI();return end
 if k==Enum.KeyCode.M and not S.preview then
  S.tool=S.tool=="PLACE" and "NONE" or "PLACE"
  refreshUI();return
 end
 if k==Enum.KeyCode.T then
  S.tool=S.tool=="TARGET" and "NONE" or "TARGET"
  S.status=S.tool=="TARGET"
   and "Кликни по чужой машине" or "Выбор отменён"
  refreshUI();return
 end
 if k==Enum.KeyCode.R and S.preview then
  targetZoom=fovToZoom(CFG.StartFOV);return
 end
 if k==Enum.KeyCode.Z and S.preview then
  if not zoomInTime then zoomInTime=os.clock();zoomBy(CFG.ZoomTap) end
  return
 end
 if k==Enum.KeyCode.X and S.preview then
  if not zoomOutTime then zoomOutTime=os.clock();zoomBy(-CFG.ZoomTap) end
  return
 end
 if input.UserInputType==Enum.UserInputType.MouseButton1 then
  if processed or pointerOverPanel() then return end
  if S.tool=="PLACE" and not S.preview then
   local hit=castMount()
   if hit then
    S.dragging=true
    mountAtWorldPoint(hit.Position,hit.Normal)
    S.status="Перемещение по кузову"
    refreshUI()
   end
  elseif S.tool=="TARGET" then
   local hit=castTarget()
   if hit and selectTarget(hit.Instance) then
    S.tool="NONE";refreshUI()
   end
  end
 end
end)
connect(UIS.InputEnded,function(input)
 if input.KeyCode==Enum.KeyCode.Z then
  zoomInTime=nil
 elseif input.KeyCode==Enum.KeyCode.X then
  zoomOutTime=nil
 end
 if input.UserInputType==Enum.UserInputType.MouseButton1 then
  if S.dragging then
   S.dragging=false
   S.status="Крепление установлено"
   refreshUI()
  end
 end
end)
connect(UIS.InputChanged,function(input,processed)
 if not S.preview or processed then return end
 if input.UserInputType==Enum.UserInputType.MouseWheel then
  zoomBy(input.Position.Z*.065)
 end
end)
connect(player.CharacterAdded,function()
 if S.preview then setPreview(false) end
 S.vehicle=nil
 S.seat=nil
 S.target=nil
 S.targetSmoothed=nil
 S.renderRotation=nil
 S.renderPosition=nil
 S.status="Сядь в автомобиль и нажми F5"
 refreshUI()
end)
refreshUI()
hideRig()
RS:BindToRenderStep("VehicleRigV31",Enum.RenderPriority.Camera.Value+3,render)
attachVehicle()
refreshUI()
print("[Vehicle Camera Rig V3.1] Loaded — chat-transcribed source")
