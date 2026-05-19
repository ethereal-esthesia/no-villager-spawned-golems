// SPDX-License-Identifier: GPL-3.0-only

package dev.shane.minecraft.novillagerspawnedgolems;

import org.bukkit.entity.EntityType;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.entity.CreatureSpawnEvent;
import org.bukkit.plugin.java.JavaPlugin;

import java.util.EnumSet;
import java.util.Set;

public final class NoVillagerSpawnedGolemsPlugin extends JavaPlugin implements Listener {

    private final Set<CreatureSpawnEvent.SpawnReason> allowedReasons = EnumSet.of(
            CreatureSpawnEvent.SpawnReason.BUILD_IRONGOLEM
    );

    @Override
    public void onEnable() {
        getServer().getPluginManager().registerEvents(this, this);
        getLogger().info("Enabled. Allowing iron golem spawn reasons: " + allowedReasons);
    }

    @Override
    public void onDisable() {
        getLogger().info("Disabled.");
    }

    @EventHandler(priority = EventPriority.HIGHEST, ignoreCancelled = true)
    public void onCreatureSpawn(CreatureSpawnEvent event) {
        if (event.getEntityType() != EntityType.IRON_GOLEM) {
            return;
        }

        CreatureSpawnEvent.SpawnReason reason = event.getSpawnReason();
        if (!allowedReasons.contains(reason)) {
            event.setCancelled(true);
            getLogger().fine(() -> "Blocked iron golem spawn with reason: " + reason);
        }
    }
}
