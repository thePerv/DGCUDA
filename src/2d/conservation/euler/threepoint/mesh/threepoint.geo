h = 0.001;
Point(1) = {0,0,0,h};
Point(2) = {1,0,0,h};
Point(3) = {1,0.5,0,h};
Point(4) = {0,0.5,0,h};

Line(1) = {1,2};
Line(2) = {2,3};
Line(3) = {3,4};
Line(4) = {4,1};

Line Loop(5) = {1,2,3,4};
Plane Surface(6) = {5};

Physical Surface (100) = {6};
Physical Line(10000) = {1};
Physical Line(20000) = {2,3,4};
