Locales = Locales or {}

Locales['en'] = {
    -- Targets
    take_parcel    = 'Take parcel',
    stow_return    = 'Stow return',
    finish_route   = 'Unload returns & finish route',
    leave_door     = 'Leave at door',
    ring_doorbell  = 'Ring doorbell',
    no_parcel      = 'No parcel',

    -- Loading
    open_loading     = 'Load the van',
    packed_score     = 'Van loaded! Packing score: %s%%',
        loading_progress = 'Loading the van...',
    route_started    = 'Route started: %s stops. Drive to the first stop!',

    -- Route flow
    next_stop       = 'Stop cleared! Head to the next stop.',
    route_done      = 'All parcels delivered! Drive back to the depot.',
    new_route       = 'New route assigned: %s stops.',
    route_finished  = 'Route finished! +$%s',

    -- HUD
    hud_loading   = 'Load the van: open its back doors at the depot',
    hud_return    = 'Route complete · Drive back to the depot',
    hud_take      = 'Take the parcel from the van',
    hud_returning = 'Return the parcel to the van',
    hud_stop      = 'Stop %s/%s',
    condition     = 'Condition',
    damaged       = 'Damaged',

    -- Parcel type labels
    type_standard  = 'Standard',
    type_signature = 'Signature',
    type_fragile   = 'Fragile',
    type_express   = 'Express',
    type_large     = 'Large',

    -- Errors
    already_carrying = 'You are already carrying a parcel.',
    no_parcel_here   = 'No parcel to take at this stop.',
    near_van         = 'Stand at the back of the van.',
    near_door        = 'Get to the delivery door.',
    wrong_address    = 'Wrong address on this label!',
    not_carrying     = 'You are not carrying a parcel.',
    needs_signature  = 'This parcel needs a signature.',
    ring_wait        = 'Someone is already at the door...',
    nobody_home      = 'Nobody is home. Bring the parcel back to the van.',
    still_carrying   = 'Stow the returns before finishing.',
    not_at_depot     = 'Bring the van back to the depot first.',
    not_return       = 'This is not a return parcel.',
    dropped_parcel   = 'You dropped the parcel.',
    placing          = 'Leaving parcel...',
    missed_home      = 'You left a "Sorry we missed you" card.',

    -- Blips
    blip_stop  = 'Delivery stop',
    blip_depot = 'Delivery depot',

    -- Admin
    admin_badtype   = 'Usage: /deliveryspot [house|business] [label...]',
    admin_spot_help = 'Record a delivery stop (stand at the door, facing it)',
    admin_debug_on  = 'Stop markers ON.',
    admin_debug_off = 'Stop markers OFF.',
    admin_no_ace    = 'You do not have permission to record stops.',
    admin_recorded  = 'Stop recorded: %s (saved to stops_recorded.lua)',
}
