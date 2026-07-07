// yard-ais-zig public API.
//
// armor:    6-bit ASCII armoring used by NMEA 0183 AIVDM / AIVDO
//           sentences. Each 6-bit AIS payload symbol maps to a
//           printable ASCII character via offset rules in ITU-R
//           M.1371 + IEC 61162-1.
//
// nmea:     NMEA 0183 checksum computation (XOR over the sentence body
//           between '$' / '!' and '*').
//
// message1: ITU-R M.1371 Message type 1 (Position Report Class A)
//           bit-field decode. 168-bit payload split into MMSI,
//           navigation status, ROT, SOG, position accuracy, longitude,
//           latitude, COG, heading, timestamp, manoeuvre, RAIM, RSM.

pub const armor = @import("armor.zig");
pub const nmea = @import("nmea.zig");
pub const message1 = @import("message1.zig");

test {
    _ = armor;
    _ = nmea;
    _ = message1;
}
