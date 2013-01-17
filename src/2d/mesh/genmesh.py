#!/usr/bin/python2
"""
genmesh.py

This file is responsible for reading the contents of the .msh file 
and translating them into something usable for CUDA.
"""

from sys import argv

def genmesh(inFilename, outFilename):
    inFile  = open(inFilename, "rb")
    outFile = open(outFilename, "wb")

    line = inFile.readline()
    while "$Nodes" not in line:
        line = inFile.readline()

    # the next line is the number of vertices
    num_verticies = int(inFile.readline())

    vertex_list = []
    for i in xrange(0,num_verticies):
        s = inFile.readline().split()
        vertex_list.append((float(s[1]), float(s[2])))
    
    # next two lines are just filler
    inFile.readline()
    inFile.readline()

    # next line is the number of elements
    num_elements = int(inFile.readline())

    side_list = []
    elem_list = []
    boundary_list = []
    # add the vertices for each element into elem_list
    for i in xrange(0,num_elements):
        s = inFile.readline().split()

        """
        # these are sides
        if len(s) == 7:
            boundary = int(s[3])
            v1 = int(s[5]) - 1
            v2 = int(s[6]) - 1
            side_list.append((vertex_list[v1], vertex_list[v2]))
            boundary_list.append(boundary)

        # and these are elements
        if len(s) == 8:
            v1 = int(s[5]) - 1
            v2 = int(s[6]) - 1
            v3 = int(s[7]) - 1
            elem_list.append((vertex_list[v1], vertex_list[v2], vertex_list[v3]))
        """
        # these are sides
        if len(s) == 7:
            boundary = int(s[3])
            v1 = int(s[5]) - 1
            v2 = int(s[6]) - 1
            # store the index of the verticies
            side_list.append((v1, v2))
            boundary_list.append(boundary)

        # and these are elements
        if len(s) == 8:
            v1 = int(s[5]) - 1
            v2 = int(s[6]) - 1
            v3 = int(s[7]) - 1
            # store the index of the verticies
            elem_list.append((v1, v2, v3))

    ##################################################
    # now that we've read in the verticies for the elements and sides,
    # we can begin creating our mesh
    ##################################################

    # number of sides we've added so far
    numsides = 0

    # stores the side number [0, 1, 2] of the left and right element's sides
    left_side_number  = [0] * (num_elements * 3) 
    right_side_number = [0] * (num_elements * 3) 

    # stores the index of the left & right elements
    left_elem  = [0] * (num_elements * 3)
    right_elem = [0] * (num_elements * 3)

    # links to side [0, 1, 2] of the element
    elem_s1 = [0] * num_elements
    elem_s2 = [0] * num_elements
    elem_s3 = [0] * num_elements

    side1 = [0] * (num_elements * 3)
    side2 = [0] * (num_elements * 3)
    side3 = [0] * (num_elements * 3)

    # these three vertices define the element
    for i, e in enumerate(elem_list):
        V1x = vertex_list[e[0]][0]
        V1y = vertex_list[e[0]][1]
        V2x = vertex_list[e[1]][0]
        V2y = vertex_list[e[1]][1]
        V3x = vertex_list[e[2]][0]
        V3y = vertex_list[e[2]][1]

        # determine whether we should add these three sides or not
        s1 = 1
        s2 = 1
        s3 = 1

        # enforce strictly positive jacobian
        J = (V2x - V1x) * (V3y - V1y) - (V3x - V1x) * (V2y - V1y)
        # swap vertex 0 and 1
        if (J < 0):
            tmp = vertex_list[e[0]]
            vertex_list[e[0]] = vertex_list[e[1]]
            vertex_list[e[1]] = tmp

        # scan through the existing sides to see if we already added it
        for j in xrange(0, numsides):
            # side 1
            if (s1 == 1 and ((side1[j] == e[0] and side2[j] == e[1])
                        or   (side2[j] == e[0] and side1[j] == e[1]))):
                s1 = 0
                # OK, we've added this side to element i
                right_elem[j] = i
                # link the added side j to this element
                elem_s1[i] = j
                right_side_number[j] = 0

        for j in xrange(0, numsides):
            # side 2
            if (s2 == 1 and ((side1[j] == e[1] and side2[j] == e[2])
                        or   (side2[j] == e[1] and side1[j] == e[2]))):
                s2 = 0
                # OK, we've added this side to element i
                right_elem[j] = i
                # link the added side to this element
                elem_s2[i] = j
                right_side_number[j] = 1

        for j in xrange(0, numsides):
            # side 3
            if (s3 == 1 and ((side1[j] == e[0] and side2[j] == e[2])
                        or   (side2[j] == e[0] and side1[j] == e[2]))):
                s3 = 0
                # OK, we've added this side to element i
                right_elem[j] = i
                # link the added side to this element
                elem_s3[i] = j
                right_side_number[j] = 2

        # if we haven't added the side already, add it
        if (s1 == 1):
            side1[numsides] = e[0]
            side2[numsides] = e[1]

            # the side number of this side
            left_side_number[numsides] = 0

            # see if this is a boundary side
            # see if this is a boundary side
            for j, s in enumerate(side_list):
                # side 0 is at this index
                if (s == (e[0], e[1]) or s == (e[1], e[0])):
                    if (boundary_list[j] == 10000):
                        right_elem[numsides] = -1
                    if (boundary_list[j] == 20000):
                        right_elem[numsides] = -2
                    if (boundary_list[j] == 30000):
                        right_elem[numsides] = -3

            # and link the element to this side
            elem_s1[i] = numsides

            # make this the left element
            left_elem[numsides] = i
            numsides += 1

        if (s2 == 1):
            side1[numsides] = e[1]
            side2[numsides] = e[2]

            # the side number of this side
            left_side_number[numsides] = 1

            # see if this is a boundary side
            for j, s in enumerate(side_list):
                # side 1 is at this index
                if (s == (e[1], e[2]) or s == (e[2], e[1])):
                    if (boundary_list[j] == 10000):
                        right_elem[numsides] = -1
                    if (boundary_list[j] == 20000):
                        right_elem[numsides] = -2
                    if (boundary_list[j] == 30000):
                        right_elem[numsides] = -3

            # and link the element to this side
            elem_s2[i] = numsides

            # make this the left element
            left_elem[numsides] = i
            numsides += 1
            
        if (s3 == 1):
            side1[numsides] = e[2]
            side2[numsides] = e[0]

            # the side number of this side
            left_side_number[numsides] = 2

            # see if this is a boundary side
            for j, s in enumerate(side_list):
                # side 2 is at this index
                if (s == (e[2], e[0]) or s == (e[0], e[2])):
                    if (boundary_list[j] == 10000):
                        right_elem[numsides] = -1
                    if (boundary_list[j] == 20000):
                        right_elem[numsides] = -2
                    if (boundary_list[j] == 30000):
                        right_elem[numsides] = -3

            # and link the element to this side
            elem_s3[i] = numsides

            # make this the left element
            left_elem[numsides] = i
            numsides += 1


    # sort the mesh so that right element items are first
    j = 0 # location after the latest right element
    for i in xrange(0, numsides):
        if right_elem[i] == -1:

            # update index for left_elem[j]
            if left_side_number[j] == 0:
                elem_s1[left_elem[j]] = i
            elif left_side_number[j] == 1:
                elem_s2[left_elem[j]] = i
            elif left_side_number[j] == 2:
                elem_s3[left_elem[j]] = i

            # update index for right_elem[j]
            if right_side_number[j] != -1:
                if right_side_number[j] == 0:
                    elem_s1[right_elem[j]] = i
                elif right_side_number[j] == 1:
                    elem_s2[right_elem[j]] = i
                elif right_side_number[j] == 2:
                    elem_s3[right_elem[j]] = i

            # update index for left_elem[i]
            if left_side_number[i] == 0:
                elem_s1[left_elem[i]] = j
            if left_side_number[i] == 1:
                elem_s2[left_elem[i]] = j
            if left_side_number[i] == 2:
                elem_s3[left_elem[i]] = j

            # swap sides i and j
            side1[i], side1[j] = side1[j], side1[i]
            side2[i], side2[j] = side2[j], side2[i]
            left_elem[i] , left_elem[j]  = left_elem[j] , left_elem[i]
            right_elem[i], right_elem[j] = right_elem[j], right_elem[i]
            left_side_number[i] , left_side_number[j]  = left_side_number[j] , left_side_number[i]
            right_side_number[i], right_side_number[j] = right_side_number[j], right_side_number[i]

            # increment j
            j += 1

    for i in xrange(0, numsides):
        if right_elem[i] == -2:

            # update index for left_elem[j]
            if left_side_number[j] == 0:
                elem_s1[left_elem[j]] = i
            elif left_side_number[j] == 1:
                elem_s2[left_elem[j]] = i
            elif left_side_number[j] == 2:
                elem_s3[left_elem[j]] = i

            # update index for right_elem[j]
            if right_side_number[j] != -1:
                if right_side_number[j] == 0:
                    elem_s1[right_elem[j]] = i
                elif right_side_number[j] == 1:
                    elem_s2[right_elem[j]] = i
                elif right_side_number[j] == 2:
                    elem_s3[right_elem[j]] = i

            # update index for left_elem[i]
            if left_side_number[i] == 0:
                elem_s1[left_elem[i]] = j
            if left_side_number[i] == 1:
                elem_s2[left_elem[i]] = j
            if left_side_number[i] == 2:
                elem_s3[left_elem[i]] = j

            # swap sides i and j
            side1[i], side1[j] = side1[j], side1[i]
            side2[i], side2[j] = side2[j], side2[i]
            left_elem[i] , left_elem[j]  = left_elem[j] , left_elem[i]
            right_elem[i], right_elem[j] = right_elem[j], right_elem[i]
            left_side_number[i] , left_side_number[j]  = left_side_number[j] , left_side_number[i]
            right_side_number[i], right_side_number[j] = right_side_number[j], right_side_number[i]

            # increment j
            j += 1

    for i in xrange(0, numsides):
        if right_elem[i] == -3:

            # update index for left_elem[j]
            if left_side_number[j] == 0:
                elem_s1[left_elem[j]] = i
            elif left_side_number[j] == 1:
                elem_s2[left_elem[j]] = i
            elif left_side_number[j] == 2:
                elem_s3[left_elem[j]] = i

            # update index for right_elem[j]
            if right_side_number[j] != -1:
                if right_side_number[j] == 0:
                    elem_s1[right_elem[j]] = i
                elif right_side_number[j] == 1:
                    elem_s2[right_elem[j]] = i
                elif right_side_number[j] == 2:
                    elem_s3[right_elem[j]] = i

            # update index for left_elem[i]
            if left_side_number[i] == 0:
                elem_s1[left_elem[i]] = j
            if left_side_number[i] == 1:
                elem_s2[left_elem[i]] = j
            if left_side_number[i] == 2:
                elem_s3[left_elem[i]] = j

            # swap sides i and j
            side1[i], side1[j] = side1[j], side1[i]
            side2[i], side2[j] = side2[j], side2[i]
            left_elem[i] , left_elem[j]  = left_elem[j] , left_elem[i]
            right_elem[i], right_elem[j] = right_elem[j], right_elem[i]
            left_side_number[i] , left_side_number[j]  = left_side_number[j] , left_side_number[i]
            right_side_number[i], right_side_number[j] = right_side_number[j], right_side_number[i]

            # increment j
            j += 1

    # write the mesh to file
    outFile.write(str(len(elem_list)) + "\n")
    for elem, s1, s2, s3 in zip(elem_list, elem_s1, elem_s2, elem_s3):
        outFile.write("%lf %lf %lf %lf %lf %lf %i %i %i\n" % (vertex_list[elem[0]][0],
                                                              vertex_list[elem[0]][1],
                                                              vertex_list[elem[1]][0],
                                                              vertex_list[elem[1]][1],
                                                              vertex_list[elem[2]][0],
                                                              vertex_list[elem[2]][1],
                                                              s1, s2, s3))

    outFile.write(str(numsides) + "\n")
    for i in xrange(0, numsides):
        outFile.write("%lf %lf %lf %lf %i %i %i %i\n" % 
                                        (vertex_list[side1[i]][0], vertex_list[side1[i]][1],
                                         vertex_list[side2[i]][0], vertex_list[side2[i]][1],
                                         left_elem[i], right_elem[i], 
                                         left_side_number[i], right_side_number[i]))

    outFile.close()

if __name__ == "__main__":
    inFilename  = argv[1] 
    outFilename = argv[2]
    genmesh(inFilename, outFilename)
