ParkTask = ADInheritsFrom(AbstractTask)

ParkTask.STATE_PATHPLANNING = 1
ParkTask.STATE_DRIVING = 2

function ParkTask:new(vehicle, destinationID)
    local o = ParkTask:create()
    o.vehicle = vehicle
    o.destinationID = destinationID
    o.actualParkDestinationName = nil
    return o
end

function ParkTask:setUp()
    self.vehicle.ad.onRouteToPark = false

    if AutoDrive.getSetting("enableParkAtJobFinished", self.vehicle) then
        local actualParkDestination = self.vehicle.ad.stateModule:getParkDestinationAtJobFinished()
        if actualParkDestination >= 1 and ADGraphManager:getMapMarkerById(actualParkDestination) ~= nil then
            self.destinationID = ADGraphManager:getMapMarkerById(actualParkDestination).id
            self.actualParkDestinationName = ADGraphManager:getMapMarkerById(actualParkDestination).name
            self.vehicle.ad.onRouteToPark = true
        else
            AutoDriveMessageEvent.sendMessage(self.vehicle, ADMessagesManager.messageTypes.ERROR, "$l10n_AD_parkVehicle_noPosSet;", 5000)
        end
    end

    if ADGraphManager:getDistanceFromNetwork(self.vehicle) > 30 then
        self.state = ParkTask.STATE_PATHPLANNING
        self.vehicle.ad.pathFinderModule:startPathPlanningToNetwork(self.destinationID)
    else
        self.state = ParkTask.STATE_DRIVING
        self.vehicle.ad.drivePathModule:setPathTo(self.destinationID)
    end
end

function ParkTask:update(dt)
    if self.state == ParkTask.STATE_PATHPLANNING then
        if self.vehicle.ad.pathFinderModule:hasFinished() then
            self.wayPoints = self.vehicle.ad.pathFinderModule:getPath()
            if self.wayPoints == nil or #self.wayPoints == 0 then
                g_logManager:error("[AutoDrive] Could not calculate path - shutting down")
                self:finished(ADTaskModule.DONT_PROPAGATE)
                self.vehicle:stopAutoDrive()
                AutoDriveMessageEvent.sendMessageOrNotification(self.vehicle, ADMessagesManager.messageTypes.ERROR, "$l10n_AD_Driver_of; %s $l10n_AD_cannot_find_path;", 5000, self.vehicle.ad.stateModule:getName())
            else
                self.vehicle.ad.drivePathModule:setWayPoints(self.wayPoints)
                self.state = ParkTask.STATE_DRIVING
            end
        else
            self.vehicle.ad.pathFinderModule:update(dt)
            self.vehicle.ad.specialDrivingModule:stopVehicle()
            self.vehicle.ad.specialDrivingModule:update(dt)
        end
    else
        local trailers, _ = AutoDrive.getTrailersOf(self.vehicle, false)
        AutoDrive.setTrailerCoverOpen(self.vehicle, trailers, false)
        if self.vehicle.ad.drivePathModule:isTargetReached() then
            self:finished()
        else
            self.vehicle.ad.drivePathModule:update(dt)
        end
    end
end

function ParkTask:abort()
end

function ParkTask:finished(propagate)
    self.vehicle.ad.taskModule:setCurrentTaskFinished(propagate)
    if self.actualParkDestinationName ~= nil then
        AutoDriveMessageEvent.sendMessageOrNotification(self.vehicle, ADMessagesManager.messageTypes.INFO, "$l10n_AD_Driver_of; %s $l10n_AD_has_reached; %s", 5000, self.vehicle.ad.stateModule:getName(), self.actualParkDestinationName)
    else
        AutoDriveMessageEvent.sendMessageOrNotification(self.vehicle, ADMessagesManager.messageTypes.ERROR, "$l10n_AD_Driver_of; %s $l10n_AD_has_reached; %s", 5000, self.vehicle.ad.stateModule:getName(), self.vehicle.ad.stateModule:getFirstMarkerName())
    end
end

function ParkTask:getI18nInfo()
    if self.state == ParkTask.STATE_PATHPLANNING then
        return "$l10n_AD_task_pathfinding;"
    elseif self.vehicle.ad.onRouteToPark == true then
        return "$l10n_AD_task_drive_to_park;"
    else
        return "$l10n_AD_task_drive_to_destination;"
    end
end
