#!/usr/bin/env python3
"""Camera path along one lane of a road ribbon (hakoniwa.road-ribbon/v1), for camera_path_client.

The ribbon points are East, North, Up (m). The output is one pose per frame in the
ROS world frame of RenderCamera (x = North, y = West, z = Up; yaw in deg from +x),
as x,y,z,yaw_deg lines.
"""
import argparse
import json
import math


def lane_centre(section, lane):
    left, right = section["points_m"][lane], section["points_m"][lane + 1]
    return [(a + b) / 2 for a, b in zip(left, right)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ribbon", help="road-ribbon JSON")
    parser.add_argument("output", help="path CSV to write")
    parser.add_argument("--lane", type=int, default=0, help="lane index between boundary lane and lane+1")
    parser.add_argument("--speed", type=float, default=10.0, help="m/s")
    parser.add_argument("--rate", type=float, default=30.0, help="frames per simulated second")
    parser.add_argument("--height", type=float, default=1.5, help="camera height above the road (m)")
    args = parser.parse_args()

    sections = json.load(open(args.ribbon))["sections"]
    points = [lane_centre(s, args.lane) for s in sections]
    # Cumulative distance along the lane.
    dist = [0.0]
    for a, b in zip(points, points[1:]):
        dist.append(dist[-1] + math.dist(a[:2], b[:2]))

    step = args.speed / args.rate
    lines = []
    i = 0
    d = 0.0
    while d <= dist[-1]:
        while dist[i + 1] < d:
            i += 1
        a, b = points[i], points[i + 1]
        t = (d - dist[i]) / max(dist[i + 1] - dist[i], 1e-9)
        east, north, up = (a[k] + (b[k] - a[k]) * t for k in range(3))
        heading = math.atan2(b[1] - a[1], b[0] - a[0])  # from East, counter-clockwise
        # ROS frame: x = North, y = West; yaw from +x (North) counter-clockwise.
        yaw = math.degrees(heading) - 90.0
        lines.append(f"{north:.3f},{-east:.3f},{up + args.height:.3f},{yaw:.2f}")
        d += step
    with open(args.output, "w") as out:
        out.write("# x,y,z,yaw_deg (ROS world frame: x=North, y=West, z=Up)\n")
        out.write("\n".join(lines) + "\n")
    print(f"{len(lines)} poses, {dist[-1]:.1f} m, {len(lines) / args.rate:.1f} s at {args.speed} m/s")


if __name__ == "__main__":
    main()
