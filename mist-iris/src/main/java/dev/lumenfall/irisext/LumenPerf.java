package dev.lumenfall.irisext;

import net.irisshaders.iris.gl.image.GlImage;
import org.lwjgl.opengl.GL30C;
import org.lwjgl.opengl.GL44C;

import java.nio.ByteBuffer;
import java.util.Map;
import java.util.Set;

public final class LumenPerf {
	public static volatile int rotation = 0;
	public static volatile int nearRadius = 80;
	public static volatile String farImage = null;
	public static volatile int farLayers = 0;
	public static volatile int farSize = 0;

	public static int slot = 0;
	public static int camX = 0, camZ = 0;
	public static boolean active = false;

	private static GlImage farImg = null;
	private static Set<GlImage> farImgFrom = null;

	private LumenPerf() {
	}

	public static void configure(Map<String, String> keys) {
		int r = parseInt(keys.get("lumenfall.shadowRotation"), 0);
		rotation = r > 1 && Integer.bitCount(r) == 1 ? r : 0;
		nearRadius = Math.max(16, parseInt(keys.get("lumenfall.nearRadius"), 80));
		farImage = keys.get("lumenfall.farImage");
		farLayers = Math.max(0, parseInt(keys.get("lumenfall.farLayers"), 0));
		farSize = Math.max(0, parseInt(keys.get("lumenfall.farSize"), 0));
		farImg = null;
		farImgFrom = null;
	}

	private static int parseInt(String s, int def) {
		if (s == null) return def;
		try {
			return Integer.parseInt(s.trim());
		} catch (NumberFormatException e) {
			return def;
		}
	}

	public static void beginShadowPass(Set<GlImage> images, double x, double z) {
		active = false;
		if (rotation == 0 || farImage == null || images == null || farSize <= 0 || farLayers <= 0) return;
		if (farImgFrom != images) {
			farImg = null;
			for (GlImage img : images) if (farImage.equals(img.getName())) farImg = img;
			farImgFrom = images;
		}
		if (farImg == null) return;
		slot = (slot + 1) & (rotation - 1);
		camX = (int) Math.floor(x);
		camZ = (int) Math.floor(z);

		int tex = farImg.getId();
		int size = farSize, layers = farLayers;
		if (size % (16 * rotation) != 0 || 2 * nearRadius + 1 > size) return;

		for (int sx = slot * 16; sx < size; sx += 16 * rotation) clear(tex, sx, 0, 16, layers, 0, size);

		int x0 = Math.floorMod(camX - nearRadius, size), z0 = Math.floorMod(camZ - nearRadius, size);
		int w = Math.min(2 * nearRadius + 1, size);
		clearWrapped(tex, size, x0, z0, w, layers);
		active = true;
	}

	private static void clearWrapped(int tex, int size, int x0, int z0, int w, int layers) {
		int wx1 = Math.min(w, size - x0), wz1 = Math.min(w, size - z0);
		clear(tex, x0, 0, wx1, layers, z0, wz1);
		if (wx1 < w) clear(tex, 0, 0, w - wx1, layers, z0, wz1);
		if (wz1 < w) clear(tex, x0, 0, wx1, layers, 0, w - wz1);
		if (wx1 < w && wz1 < w) clear(tex, 0, 0, w - wx1, layers, 0, w - wz1);
	}

	private static void clear(int tex, int x, int y, int w, int h, int z, int d) {
		GL44C.glClearTexSubImage(tex, 0, x, y, z, w, h, d, GL30C.GL_RED_INTEGER, GL30C.GL_UNSIGNED_INT, (ByteBuffer) null);
	}

	public static boolean drawSection(int chunkX, int chunkZ) {
		int bx = chunkX << 4, bz = chunkZ << 4;
		if (bx <= camX + nearRadius && bx + 15 >= camX - nearRadius && bz <= camZ + nearRadius && bz + 15 >= camZ - nearRadius) return true;
		return (chunkX & (rotation - 1)) == slot;
	}
}
