package dev.lumenfall.irisext;

import it.unimi.dsi.fastutil.ints.Int2IntMap;
import it.unimi.dsi.fastutil.ints.Int2IntMaps;
import it.unimi.dsi.fastutil.objects.Object2IntMap;
import net.caffeinemc.mods.sodium.client.world.LevelSlice;
import net.irisshaders.iris.shaderpack.materialmap.WorldRenderingSettings;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.block.SnowLayerBlock;
import net.minecraft.world.level.block.state.BlockState;

public final class BlockNeighborData {
	public static volatile boolean enabled = false;

	public static volatile Int2IntMap groups = Int2IntMaps.EMPTY_MAP;

	public static final int FACE_BITS_SHIFT = 26;
	public static final int MASK_26 = (1 << 26) - 1;

	public static final int FACE_POS_X = 0, FACE_NEG_X = 1, FACE_POS_Y = 2, FACE_NEG_Y = 3, FACE_POS_Z = 4, FACE_NEG_Z = 5;

	public int sameBlock;
	public int nonAir;
	public int solid;

	public final int[] faceIds = new int[6];
	private final BlockPos.MutableBlockPos scratch = new BlockPos.MutableBlockPos();

	private static boolean sameKind(int id, int selfId, int selfGroup, Int2IntMap groupOf) {
		return id != -1 && (id == selfId || (selfGroup != -1 && groupOf.getOrDefault(id, -2) == selfGroup));
	}

	public static int bitIndex(int dx, int dy, int dz) {
		int i = (dx + 1) + (dy + 1) * 3 + (dz + 1) * 9;
		return i < 13 ? i : i - 1;
	}

	private static int faceIndex(int dx, int dy, int dz) {
		if (dx == 1) return FACE_POS_X;
		if (dx == -1) return FACE_NEG_X;
		if (dy == 1) return FACE_POS_Y;
		if (dy == -1) return FACE_NEG_Y;
		if (dz == 1) return FACE_POS_Z;
		return FACE_NEG_Z;
	}

	public void clear() {
		sameBlock = 0;
		nonAir = 0;
		solid = 0;
		for (int i = 0; i < 6; i++) faceIds[i] = 0;
	}

	public void copyFrom(BlockNeighborData other) {
		this.sameBlock = other.sameBlock;
		this.nonAir = other.nonAir;
		this.solid = other.solid;
		System.arraycopy(other.faceIds, 0, this.faceIds, 0, 6);
	}

	public void compute(LevelSlice slice, int x, int y, int z, BlockState self) {
		clear();
		if (!enabled) return;

		Object2IntMap<BlockState> ids = WorldRenderingSettings.INSTANCE.getBlockStateIds();
		int selfId = ids == null ? -1 : ids.getOrDefault(self, -1);
		Int2IntMap groupOf = groups;
		int selfGroup = selfId == -1 ? -1 : groupOf.getOrDefault(selfId, -1);

		int same = 0, filled = 0, opaque = 0;
		int faceFluid = 0, faceEmits = 0, faceSameId = 0;

		for (int dz = -1; dz <= 1; dz++) {
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					if (dx == 0 && dy == 0 && dz == 0) continue;

					BlockState n = slice.getBlockState(x + dx, y + dy, z + dz);
					int bit = 1 << bitIndex(dx, dy, dz);

					boolean air = n.isAir();
					if (!air && (n.getBlock() instanceof SnowLayerBlock
						|| !n.getCollisionShape(slice, scratch.set(x + dx, y + dy, z + dz)).isEmpty())) filled |= bit;
					if (n.getBlock() == self.getBlock() || (!n.getFluidState().isEmpty() && n.getFluidState().createLegacyBlock().getBlock() == self.getBlock())
						|| (selfId != -1 && !air && sameKind(ids.getOrDefault(n, -1), selfId, selfGroup, groupOf))) same |= bit;
					if (n.isSolidRender()) opaque |= bit;

					if (Math.abs(dx) + Math.abs(dy) + Math.abs(dz) == 1) {
						int face = faceIndex(dx, dy, dz);
						int fbit = 1 << face;
						int nId = ids == null ? -1 : ids.getOrDefault(n, -1);
						faceIds[face] = (nId + 1) & 0xFFFF;

						if (!n.getFluidState().isEmpty()) faceFluid |= fbit;
						if (n.getLightEmission() > 0) faceEmits |= fbit;
						if (selfId != -1 && nId == selfId) faceSameId |= fbit;
					}
				}
			}
		}

		this.sameBlock = (same & MASK_26) | (faceFluid << FACE_BITS_SHIFT);
		this.nonAir = (filled & MASK_26) | (faceEmits << FACE_BITS_SHIFT);
		this.solid = (opaque & MASK_26) | (faceSameId << FACE_BITS_SHIFT);
	}

	public int packIds(int face) {
		int front = face >= 0 && face < 6 ? faceIds[face] : 0;
		return (front & 0xFFFF) | ((faceIds[FACE_NEG_Y] & 0xFFFF) << 16);
	}

	public static int faceFromNormal(float nx, float ny, float nz) {
		float ax = Math.abs(nx), ay = Math.abs(ny), az = Math.abs(nz);
		if (ax == 0 && ay == 0 && az == 0) return -1;
		if (ax >= ay && ax >= az) return nx >= 0 ? FACE_POS_X : FACE_NEG_X;
		if (ay >= az) return ny >= 0 ? FACE_POS_Y : FACE_NEG_Y;
		return nz >= 0 ? FACE_POS_Z : FACE_NEG_Z;
	}
}
