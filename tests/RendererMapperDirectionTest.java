import com.luka.carplay.routeguidance.ManeuverMapper;
import com.luka.carplay.routeguidance.RendererMapper;

public final class RendererMapperDirectionTest {
    private static void expect(String name, int expected, int actual) {
        if (expected != actual) {
            throw new AssertionError(name + ": expected " + expected + ", got " + actual);
        }
    }

    public static void main(String[] args) {
        int uturn = ManeuverMapper.MT_U_TURN;

        expect("renderer left U-turn from CarPlay angle", -1,
            RendererMapper.mapDirection(uturn, -180, ManeuverMapper.DRIVING_SIDE_LEFT));
        expect("renderer right U-turn from CarPlay angle", 1,
            RendererMapper.mapDirection(uturn, 180, ManeuverMapper.DRIVING_SIDE_RIGHT));
        expect("renderer China RHT fallback", -1,
            RendererMapper.mapDirection(uturn, 1000, ManeuverMapper.DRIVING_SIDE_RIGHT));
        expect("renderer fallback ignores bad driving-side data", -1,
            RendererMapper.mapDirection(uturn, 1000, ManeuverMapper.DRIVING_SIDE_LEFT));

        expect("BAP left U-turn from CarPlay angle", ManeuverMapper.DIR_LEFT,
            ManeuverMapper.map(uturn, -180,
                ManeuverMapper.JUNCTION_SINGLE_INTERSECTION,
                ManeuverMapper.DRIVING_SIDE_LEFT)[1]);
        expect("BAP right U-turn from CarPlay angle", ManeuverMapper.DIR_RIGHT,
            ManeuverMapper.map(uturn, 180,
                ManeuverMapper.JUNCTION_SINGLE_INTERSECTION,
                ManeuverMapper.DRIVING_SIDE_RIGHT)[1]);
        expect("BAP China RHT fallback", ManeuverMapper.DIR_LEFT,
            ManeuverMapper.map(uturn, 1000,
                ManeuverMapper.JUNCTION_SINGLE_INTERSECTION,
                ManeuverMapper.DRIVING_SIDE_LEFT)[1]);

        System.out.println("RendererMapperDirectionTest: PASS");
    }
}
