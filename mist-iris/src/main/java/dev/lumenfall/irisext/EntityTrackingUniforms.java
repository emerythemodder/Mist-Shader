package dev.lumenfall.irisext;

import it.unimi.dsi.fastutil.objects.Object2IntFunction;
import net.irisshaders.iris.uniforms.CameraUniforms;
import net.irisshaders.iris.uniforms.CapturedRenderingState;
import net.irisshaders.iris.uniforms.SystemTimeUniforms;
import net.irisshaders.iris.gl.uniform.UniformHolder;
import net.irisshaders.iris.shaderpack.materialmap.NamespacedId;
import net.irisshaders.iris.shaderpack.materialmap.WorldRenderingSettings;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;
import net.minecraft.tags.FluidTags;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.MobCategory;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.LightLayer;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.EntityHitResult;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;
import org.joml.Vector3d;
import org.joml.Vector4f;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import static net.irisshaders.iris.gl.uniform.UniformUpdateFrequency.PER_FRAME;

public final class EntityTrackingUniforms {
	public static final int MAX_TRACKED = Integer.getInteger("iris.entityTracking.max", 32);
	public static final float RADIUS = Float.parseFloat(System.getProperty("iris.entityTracking.radius", "64"));

	public static final int NEIGHBORHOOD_RADIUS = Math.max(0, Integer.getInteger("iris.entityTracking.neighborhoodRadius", 1));
	public static final int NEIGHBORHOOD_SIDE = NEIGHBORHOOD_RADIUS * 2 + 1;
	public static final int NEIGHBORHOOD_SIZE = NEIGHBORHOOD_SIDE * NEIGHBORHOOD_SIDE * NEIGHBORHOOD_SIDE;

	public static final int FLAG_ON_FIRE = 1;
	public static final int FLAG_GLOWING = 2;
	public static final int FLAG_INVISIBLE = 4;
	public static final int FLAG_SNEAKING = 8;
	public static final int FLAG_SPRINTING = 16;
	public static final int FLAG_HOSTILE = 32;
	public static final int FLAG_PLAYER = 64;
	public static final int FLAG_HURT = 128;
	public static final int FLAG_ON_GROUND = 256;
	public static final int FLAG_IN_WATER = 512;
	public static final int FLAG_LIVING = 1024;

	public static final int STATUS_BABY = 1;
	public static final int STATUS_SLEEPING = 2;
	public static final int STATUS_USING_ITEM = 4;
	public static final int STATUS_PASSENGER = 8;
	public static final int STATUS_HAS_PASSENGERS = 16;
	public static final int STATUS_DYING = 32;
	public static final int STATUS_FROZEN = 64;
	public static final int STATUS_IN_LAVA = 128;
	public static final int STATUS_UNDERWATER = 256;
	public static final int STATUS_CROSSHAIR_TARGET = 512;

	public static final int BLOCK_AIR = 1;
	public static final int BLOCK_SOLID_RENDER = 2;
	public static final int BLOCK_HAS_FLUID = 4;
	public static final int BLOCK_WATER = 8;
	public static final int BLOCK_LAVA = 16;
	public static final int BLOCK_FULL_COLLISION = 32;
	public static final int BLOCK_CAN_OCCLUDE = 64;
	public static final int BLOCK_FLUID_SOURCE = 128;
	public static final int BLOCK_EMISSION_SHIFT = 8;
	public static final int BLOCK_FLUID_AMOUNT_SHIFT = 12;

	private static final int[][] FACE_OFFSETS = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};

	private static final Snapshot SNAPSHOT = new Snapshot();

	private EntityTrackingUniforms() {
	}

	public static void addEntityTrackingUniforms(UniformHolder u) {
		u.uniform1i(PER_FRAME, "trackedEntityCount", () -> snapshot().count);
		u.uniform1f(PER_FRAME, "trackedEntityRadius", () -> RADIUS);
		u.uniform1i(PER_FRAME, "nearbyEntityCount", () -> snapshot().nearbyCount);
		u.uniform1i(PER_FRAME, "nearbyHostileCount", () -> snapshot().hostileCount);
		u.uniform1i(PER_FRAME, "nearbyPlayerCount", () -> snapshot().playerCount);
		u.uniform1i(PER_FRAME, "nearbyLivingCount", () -> snapshot().livingCount);
		u.uniform4f(PER_FRAME, "nearestEntityPosition", () -> snapshot().nearestEntity);
		u.uniform4f(PER_FRAME, "nearestHostilePosition", () -> snapshot().nearestHostile);
		u.uniform4f(PER_FRAME, "nearestPlayerPosition", () -> snapshot().nearestPlayer);

		u.uniform3d(PER_FRAME, "trackedPlayerVelocity", () -> snapshot().playerVelocity);
		u.uniform4f(PER_FRAME, "playerFeetPosition", () -> snapshot().playerFeet);
		u.uniform4f(PER_FRAME, "playerFeetBlock", () -> snapshot().playerFeetBlock);
		u.uniform4f(PER_FRAME, "playerBelowBlock", () -> snapshot().playerBelowBlock);
		u.uniform4f(PER_FRAME, "playerEyeBlock", () -> snapshot().playerEyeBlock);
		u.uniform4f(PER_FRAME, "playerFeetLight", () -> snapshot().playerFeetLight);
		u.uniform4f(PER_FRAME, "playerNeighborhoodOrigin", () -> snapshot().neighborhoodOrigin);
		u.uniform1i(PER_FRAME, "playerNeighborhoodRadius", () -> NEIGHBORHOOD_RADIUS);
		for (int i = 0; i < NEIGHBORHOOD_SIZE; i++) {
			final int slot = i;
			u.uniform4f(PER_FRAME, "playerNeighborhood[" + i + "]", () -> snapshot().neighborhood[slot]);
		}

		u.uniform1i(PER_FRAME, "crosshairTargetType", () -> snapshot().crosshairType);
		u.uniform4f(PER_FRAME, "selectedBlockInfo", () -> snapshot().selectedBlock);
		u.uniform4f(PER_FRAME, "selectedBlockPosition", () -> snapshot().selectedBlockPos);
		u.uniform4f(PER_FRAME, "selectedBlockHit", () -> snapshot().selectedBlockHit);
		for (int i = 0; i < 6; i++) {
			final int slot = i;
			u.uniform4f(PER_FRAME, "selectedBlockNeighbors[" + i + "]", () -> snapshot().selectedNeighbors[slot]);
		}
		u.uniform4f(PER_FRAME, "selectedEntityPosition", () -> snapshot().selectedEntityPos);
		u.uniform4f(PER_FRAME, "selectedEntityInfo", () -> snapshot().selectedEntityInfo);

		for (int i = 0; i < MAX_TRACKED; i++) {
			final int s = i;
			u.uniform4f(PER_FRAME, "trackedEntityPosition[" + i + "]", () -> snapshot().position[s]);
			u.uniform4f(PER_FRAME, "trackedEntityEye[" + i + "]", () -> snapshot().eye[s]);
			u.uniform4f(PER_FRAME, "trackedEntityVelocity[" + i + "]", () -> snapshot().velocity[s]);
			u.uniform4f(PER_FRAME, "trackedEntityForward[" + i + "]", () -> snapshot().forward[s]);
			u.uniform4f(PER_FRAME, "trackedEntityRotation[" + i + "]", () -> snapshot().rotation[s]);
			u.uniform4f(PER_FRAME, "trackedEntityInfo[" + i + "]", () -> snapshot().info[s]);
			u.uniform4f(PER_FRAME, "trackedEntityStatus[" + i + "]", () -> snapshot().status[s]);
			u.uniform4f(PER_FRAME, "trackedEntityFeetBlock[" + i + "]", () -> snapshot().feetBlock[s]);
			u.uniform4f(PER_FRAME, "trackedEntityBelowBlock[" + i + "]", () -> snapshot().belowBlock[s]);
			u.uniform4f(PER_FRAME, "trackedEntityLight[" + i + "]", () -> snapshot().light[s]);
		}
	}

	private static Snapshot snapshot() {
		int frame = SystemTimeUniforms.COUNTER.getAsInt();
		ClientLevel level = Minecraft.getInstance().level;

		if (SNAPSHOT.frame != frame || SNAPSHOT.level != level) {
			SNAPSHOT.frame = frame;
			SNAPSHOT.level = level;
			SNAPSHOT.rebuild(level);
		}

		return SNAPSHOT;
	}

	private record Candidate(Entity entity, double distanceSq) {
	}

	private static final class Snapshot {
		int frame = -1;
		ClientLevel level;

		int count, nearbyCount, hostileCount, playerCount, livingCount;
		final Vector4f nearestEntity = new Vector4f(0, 0, 0, -1);
		final Vector4f nearestHostile = new Vector4f(0, 0, 0, -1);
		final Vector4f nearestPlayer = new Vector4f(0, 0, 0, -1);

		final Vector3d playerVelocity = new Vector3d();
		final Vector4f playerFeet = new Vector4f();
		final Vector4f playerFeetBlock = new Vector4f();
		final Vector4f playerBelowBlock = new Vector4f();
		final Vector4f playerEyeBlock = new Vector4f();
		final Vector4f playerFeetLight = new Vector4f();
		final Vector4f neighborhoodOrigin = new Vector4f();
		final Vector4f[] neighborhood = filled(NEIGHBORHOOD_SIZE);

		int crosshairType;
		final Vector4f selectedBlock = new Vector4f();
		final Vector4f selectedBlockPos = new Vector4f();
		final Vector4f selectedBlockHit = new Vector4f();
		final Vector4f[] selectedNeighbors = filled(6);
		final Vector4f selectedEntityPos = new Vector4f(0, 0, 0, -1);
		final Vector4f selectedEntityInfo = new Vector4f();

		final Vector4f[] position = filled(MAX_TRACKED);
		final Vector4f[] eye = filled(MAX_TRACKED);
		final Vector4f[] velocity = filled(MAX_TRACKED);
		final Vector4f[] forward = filled(MAX_TRACKED);
		final Vector4f[] rotation = filled(MAX_TRACKED);
		final Vector4f[] info = filled(MAX_TRACKED);
		final Vector4f[] status = filled(MAX_TRACKED);
		final Vector4f[] feetBlock = filled(MAX_TRACKED);
		final Vector4f[] belowBlock = filled(MAX_TRACKED);
		final Vector4f[] light = filled(MAX_TRACKED);

		private final List<Candidate> candidates = new ArrayList<>();
		private final BlockPos.MutableBlockPos mpos = new BlockPos.MutableBlockPos();

		private static Vector4f[] filled(int n) {
			Vector4f[] arr = new Vector4f[n];
			for (int i = 0; i < n; i++) arr[i] = new Vector4f();
			return arr;
		}

		private static void zero(Vector4f[] arr) {
			for (Vector4f v : arr) v.zero();
		}

		private void reset() {
			count = nearbyCount = hostileCount = playerCount = livingCount = 0;
			nearestEntity.set(0, 0, 0, -1);
			nearestHostile.set(0, 0, 0, -1);
			nearestPlayer.set(0, 0, 0, -1);
			playerVelocity.set(0);
			playerFeet.zero();
			playerFeetBlock.zero();
			playerBelowBlock.zero();
			playerEyeBlock.zero();
			playerFeetLight.zero();
			neighborhoodOrigin.zero();
			zero(neighborhood);
			crosshairType = 0;
			selectedBlock.zero();
			selectedBlockPos.zero();
			selectedBlockHit.set(0, 0, 0, -1);
			zero(selectedNeighbors);
			selectedEntityPos.set(0, 0, 0, -1);
			selectedEntityInfo.zero();
			zero(position);
			zero(eye);
			zero(velocity);
			zero(forward);
			zero(rotation);
			zero(info);
			zero(status);
			zero(feetBlock);
			zero(belowBlock);
			zero(light);
		}

		void rebuild(ClientLevel level) {
			reset();

			Minecraft mc = Minecraft.getInstance();
			if (level == null || mc.getCameraEntity() == null) return;

			float tickDelta = CapturedRenderingState.INSTANCE.getTickDelta();
			Vector3d cam = CameraUniforms.getUnshiftedCameraPosition();
			Entity cameraEntity = mc.getCameraEntity();
			Object2IntFunction<NamespacedId> entityIds = WorldRenderingSettings.INSTANCE.getEntityIds();

			HitResult hit = mc.hitResult;
			Entity targetedEntity = hit instanceof EntityHitResult ehr && hit.getType() == HitResult.Type.ENTITY ? ehr.getEntity() : null;

			buildPlayer(level, mc, cam, tickDelta);
			buildCrosshair(level, hit, cam, tickDelta, entityIds);
			buildEntities(level, cameraEntity, cam, tickDelta, entityIds, targetedEntity);
		}

		private void buildPlayer(ClientLevel level, Minecraft mc, Vector3d cam, float tickDelta) {
			Entity player = mc.player != null ? mc.player : mc.getCameraEntity();

			Vec3 feet = player.getPosition(tickDelta);
			Vec3 prev = player.getPosition(0.0f);
			Vec3 now = player.getPosition(1.0f);
			playerVelocity.set(now.x - prev.x, now.y - prev.y, now.z - prev.z);
			playerFeet.set((float) (feet.x - cam.x), (float) (feet.y - cam.y), (float) (feet.z - cam.z), player.getEyeHeight());

			BlockPos feetPos = BlockPos.containing(feet.x, feet.y, feet.z);

			BlockPos belowPos = BlockPos.containing(feet.x, feet.y - 0.2, feet.z);
			if (belowPos.equals(feetPos)) belowPos = feetPos.below();
			Vec3 eyeVec = player.getEyePosition(tickDelta);

			encodeBlockWithLight(level, feetPos, playerFeetBlock);
			encodeBlockWithLight(level, belowPos, playerBelowBlock);
			encodeBlockWithLight(level, BlockPos.containing(eyeVec.x, eyeVec.y, eyeVec.z), playerEyeBlock);
			playerFeetLight.set(
				level.getBrightness(LightLayer.BLOCK, feetPos),
				level.getBrightness(LightLayer.SKY, feetPos),
				level.getBrightness(LightLayer.BLOCK, BlockPos.containing(eyeVec.x, eyeVec.y, eyeVec.z)),
				level.getBrightness(LightLayer.SKY, BlockPos.containing(eyeVec.x, eyeVec.y, eyeVec.z)));

			neighborhoodOrigin.set((float) (feetPos.getX() - cam.x), (float) (feetPos.getY() - cam.y), (float) (feetPos.getZ() - cam.z), NEIGHBORHOOD_SIDE);

			int r = NEIGHBORHOOD_RADIUS;
			int idx = 0;

			for (int dz = -r; dz <= r; dz++) {
				for (int dy = -r; dy <= r; dy++) {
					for (int dx = -r; dx <= r; dx++) {
						mpos.set(feetPos.getX() + dx, feetPos.getY() + dy, feetPos.getZ() + dz);
						encodeBlockWithLight(level, mpos, neighborhood[idx++]);
					}
				}
			}
		}

		private void buildCrosshair(ClientLevel level, HitResult hit, Vector3d cam, float tickDelta, Object2IntFunction<NamespacedId> entityIds) {
			if (hit == null || hit.getType() == HitResult.Type.MISS) {
				crosshairType = 0;
				return;
			}

			Vec3 loc = hit.getLocation();
			float hitDist = (float) Math.sqrt((loc.x - cam.x) * (loc.x - cam.x) + (loc.y - cam.y) * (loc.y - cam.y) + (loc.z - cam.z) * (loc.z - cam.z));

			if (hit instanceof BlockHitResult bhr && hit.getType() == HitResult.Type.BLOCK) {
				crosshairType = 1;
				BlockPos pos = bhr.getBlockPos();
				encodeBlockWithLight(level, pos, selectedBlock);
				selectedBlockPos.set((float) (pos.getX() - cam.x), (float) (pos.getY() - cam.y), (float) (pos.getZ() - cam.z), faceIndex(bhr));
				selectedBlockHit.set((float) (loc.x - cam.x), (float) (loc.y - cam.y), (float) (loc.z - cam.z), hitDist);

				for (int f = 0; f < 6; f++) {
					int[] o = FACE_OFFSETS[f];
					mpos.set(pos.getX() + o[0], pos.getY() + o[1], pos.getZ() + o[2]);
					encodeBlockWithLight(level, mpos, selectedNeighbors[f]);
				}
			} else if (hit instanceof EntityHitResult ehr && hit.getType() == HitResult.Type.ENTITY) {
				crosshairType = 2;
				Entity e = ehr.getEntity();
				Vec3 p = e.getPosition(tickDelta);
				selectedEntityPos.set((float) (p.x - cam.x), (float) (p.y - cam.y), (float) (p.z - cam.z), hitDist);
				selectedEntityInfo.set(entityId(entityIds, e), entityFlags(e), e.getBbWidth(), e.getBbHeight());
			}
		}

		private static int faceIndex(BlockHitResult bhr) {
			return switch (bhr.getDirection()) {
				case EAST -> 0;
				case WEST -> 1;
				case UP -> 2;
				case DOWN -> 3;
				case SOUTH -> 4;
				case NORTH -> 5;
			};
		}

		private void buildEntities(ClientLevel level, Entity cameraEntity, Vector3d cam, float tickDelta,
								   Object2IntFunction<NamespacedId> entityIds, Entity targetedEntity) {
			double radiusSq = (double) RADIUS * RADIUS;
			candidates.clear();
			double bestAny = Double.MAX_VALUE, bestHostile = Double.MAX_VALUE, bestPlayer = Double.MAX_VALUE;

			for (Entity entity : level.entitiesForRendering()) {
				if (entity == cameraEntity || entity.isRemoved()) continue;

				Vec3 p = entity.getPosition(tickDelta);
				double dx = p.x - cam.x, dy = p.y - cam.y, dz = p.z - cam.z;
				double dSq = dx * dx + dy * dy + dz * dz;
				if (dSq > radiusSq) continue;

				nearbyCount++;
				float dist = (float) Math.sqrt(dSq);

				if (dSq < bestAny) {
					bestAny = dSq;
					nearestEntity.set((float) dx, (float) dy, (float) dz, dist);
				}
				if (entity instanceof LivingEntity) livingCount++;
				if (isHostile(entity)) {
					hostileCount++;
					if (dSq < bestHostile) {
						bestHostile = dSq;
						nearestHostile.set((float) dx, (float) dy, (float) dz, dist);
					}
				}
				if (entity instanceof Player) {
					playerCount++;
					if (dSq < bestPlayer) {
						bestPlayer = dSq;
						nearestPlayer.set((float) dx, (float) dy, (float) dz, dist);
					}
				}

				candidates.add(new Candidate(entity, dSq));
			}

			candidates.sort(Comparator.comparingDouble(Candidate::distanceSq));
			count = Math.min(candidates.size(), MAX_TRACKED);

			for (int i = 0; i < count; i++) {
				Entity e = candidates.get(i).entity();

				Vec3 p = e.getPosition(tickDelta);
				position[i].set((float) (p.x - cam.x), (float) (p.y - cam.y), (float) (p.z - cam.z), (float) Math.sqrt(candidates.get(i).distanceSq()));

				Vec3 eyeVec = e.getEyePosition(tickDelta);
				eye[i].set((float) (eyeVec.x - cam.x), (float) (eyeVec.y - cam.y), (float) (eyeVec.z - cam.z), e.getEyeHeight());

				Vec3 now = e.getPosition(1.0f);
				Vec3 prev = e.getPosition(0.0f);
				float vx = (float) (now.x - prev.x), vy = (float) (now.y - prev.y), vz = (float) (now.z - prev.z);
				velocity[i].set(vx, vy, vz, (float) Math.sqrt(vx * vx + vy * vy + vz * vz));

				Vec3 fwd = e.getForward();
				float health = -1.0f;
				LivingEntity living = e instanceof LivingEntity l ? l : null;
				if (living != null && living.getMaxHealth() > 0) {
					health = Math.clamp(living.getHealth() / living.getMaxHealth(), 0.0f, 1.0f);
				}
				forward[i].set((float) fwd.x, (float) fwd.y, (float) fwd.z, health);

				rotation[i].set(
					(float) Math.toRadians(e.getYRot()),
					(float) Math.toRadians(e.getXRot()),
					(float) Math.toRadians(e.getYHeadRot()),
					e.tickCount + tickDelta);

				info[i].set(entityId(entityIds, e), entityFlags(e), e.getBbWidth(), e.getBbHeight());

				float armor = 0, air = 1;
				if (living != null) {
					armor = living.getArmorValue();
					air = e.getMaxAirSupply() > 0 ? Math.clamp((float) e.getAirSupply() / e.getMaxAirSupply(), 0.0f, 1.0f) : 1.0f;
				}
				status[i].set(armor, air, Math.max(0, e.getRemainingFireTicks()), statusFlags(e, living, e == targetedEntity));

				BlockPos feetPos = BlockPos.containing(p.x, p.y, p.z);
				BlockPos belowPos = BlockPos.containing(p.x, p.y - 0.2, p.z);
				if (belowPos.equals(feetPos)) belowPos = feetPos.below();
				encodeBlockWithLight(level, feetPos, feetBlock[i]);
				encodeBlockWithLight(level, belowPos, belowBlock[i]);

				BlockPos eyePos = BlockPos.containing(eyeVec.x, eyeVec.y, eyeVec.z);
				light[i].set(
					level.getBrightness(LightLayer.BLOCK, feetPos),
					level.getBrightness(LightLayer.SKY, feetPos),
					level.getBrightness(LightLayer.BLOCK, eyePos),
					level.getBrightness(LightLayer.SKY, eyePos));
			}
		}

		private static void encodeBlockWithLight(ClientLevel level, BlockPos pos, Vector4f out) {
			BlockState state = level.getBlockState(pos);
			out.set(blockId(state), level.getBrightness(LightLayer.BLOCK, pos), level.getBrightness(LightLayer.SKY, pos), blockFlags(level, pos, state));
		}
	}

	private static int blockId(BlockState state) {
		var ids = WorldRenderingSettings.INSTANCE.getBlockStateIds();
		return ids == null ? 0 : ids.getInt(state);
	}

	private static int blockFlags(ClientLevel level, BlockPos pos, BlockState state) {
		int f = 0;
		if (state.isAir()) f |= BLOCK_AIR;
		if (state.isSolidRender()) f |= BLOCK_SOLID_RENDER;
		if (state.canOcclude()) f |= BLOCK_CAN_OCCLUDE;
		if (state.isCollisionShapeFullBlock(level, pos)) f |= BLOCK_FULL_COLLISION;

		FluidState fluid = state.getFluidState();
		if (!fluid.isEmpty()) {
			f |= BLOCK_HAS_FLUID;
			if (fluid.is(FluidTags.WATER)) f |= BLOCK_WATER;
			if (fluid.is(FluidTags.LAVA)) f |= BLOCK_LAVA;
			if (fluid.isSource()) f |= BLOCK_FLUID_SOURCE;
			f |= (Math.min(fluid.getAmount(), 15) & 15) << BLOCK_FLUID_AMOUNT_SHIFT;
		}

		f |= (Math.min(state.getLightEmission(), 15) & 15) << BLOCK_EMISSION_SHIFT;
		return f;
	}

	private static boolean isHostile(Entity entity) {
		return entity.getType().getCategory() == MobCategory.MONSTER;
	}

	private static int entityFlags(Entity e) {
		int f = 0;
		if (e.isOnFire()) f |= FLAG_ON_FIRE;
		if (e.isCurrentlyGlowing()) f |= FLAG_GLOWING;
		if (e.isInvisible()) f |= FLAG_INVISIBLE;
		if (e.isShiftKeyDown()) f |= FLAG_SNEAKING;
		if (e.isSprinting()) f |= FLAG_SPRINTING;
		if (isHostile(e)) f |= FLAG_HOSTILE;
		if (e instanceof Player) f |= FLAG_PLAYER;
		if (e.onGround()) f |= FLAG_ON_GROUND;
		if (e.isInWater()) f |= FLAG_IN_WATER;
		if (e instanceof LivingEntity living) {
			f |= FLAG_LIVING;
			if (living.hurtTime > 0) f |= FLAG_HURT;
		}
		return f;
	}

	private static int statusFlags(Entity e, LivingEntity living, boolean targeted) {
		int f = 0;
		if (e.isPassenger()) f |= STATUS_PASSENGER;
		if (e.isVehicle()) f |= STATUS_HAS_PASSENGERS;
		if (e.isFullyFrozen()) f |= STATUS_FROZEN;
		if (e.isInLava()) f |= STATUS_IN_LAVA;
		if (e.isUnderWater()) f |= STATUS_UNDERWATER;
		if (targeted) f |= STATUS_CROSSHAIR_TARGET;
		if (living != null) {
			if (living.isBaby()) f |= STATUS_BABY;
			if (living.isSleeping()) f |= STATUS_SLEEPING;
			if (living.isUsingItem()) f |= STATUS_USING_ITEM;
			if (living.isDeadOrDying()) f |= STATUS_DYING;
		}
		return f;
	}

	private static int entityId(Object2IntFunction<NamespacedId> idMap, Entity e) {
		if (idMap == null) return 0;
		Identifier id = BuiltInRegistries.ENTITY_TYPE.getKey(e.getType());
		if (id == null) return 0;
		return idMap.applyAsInt(new NamespacedId(id.getNamespace(), id.getPath()));
	}
}
