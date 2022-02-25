import pysam
import tiddit_signal
import numpy
import math
import os
import DBSCAN

def read_contigs(aligned_contigs,prefix,sample_id,min_size):
	samfile = pysam.AlignmentFile(aligned_contigs, "r")
	bam_header=samfile.header
	

	split_contigs={}
	for chrA in bam_header["SQ"]:
		for chrB in bam_header["SQ"]:
			if chrA["SN"] <= chrB["SN"]:

				if not chrA["SN"] in split_contigs:
					split_contigs[chrA["SN"]] = {}

				split_contigs[chrA["SN"]][chrB["SN"]]={}

	for read in samfile.fetch(until_eof=True):

		if read.is_unmapped:
			continue

		if read.has_tag("SA") and not (read.is_supplementary or read.is_secondary):
			split_contigs=tiddit_signal.SA_analysis(read,-2,split_contigs,"SA")
		elif read.has_tag("XA") and not (read.is_supplementary or read.is_secondary):
			XA=read.get_tag("XA")
			if XA.count(";") == 1:
				if "-" in XA:
					XA=XA.replace("-","")
					xa_list=XA.split(",")
					xa_list.insert(2,"-")
					XA=",".join(xa_list)
				else:
					XA=XA.replace("+","")
					xa_list=XA.split(",")
					xa_list.insert(2,"+")
					XA=",".join(xa_list)

				read.set_tag("XA",XA)
				split_contigs=tiddit_signal.SA_analysis(read,-2,split_contigs,"XA")

		elif not (read.is_supplementary or read.is_secondary) and len(read.cigartuples) > 2:

			current_bp=read.reference_start
			for i in range(0,len(read.cigartuples)-1):
				if read.cigartuples[i][0] == 2 and read.cigartuples[i][1] > min_size:
					split_contigs[read.reference_name][read.reference_name]["{}_d_{}".format(read.query_name,i)]=[current_bp,read.is_reverse,current_bp+read.cigartuples[i][1],read.is_reverse]
				current_bp+=read.cigartuples[i][1]

	for chrA in split_contigs:
		for chrB in split_contigs[chrA]:
			f=open("{}_tiddit/contigs_{}_{}_{}.tab".format(prefix,sample_id,chrA,chrB),"w")

			for fragment in split_contigs[chrA][chrB]:

				f.write("{}\t{}\n".format(fragment,"\t".join(map(str, split_contigs[chrA][chrB][fragment] )))  )

			f.close()

def main(prefix,sample_id,library,contigs,coverage_data,args):

	f=open("{}_tiddit/clips.fa".format(prefix),"w")	
	for chr in contigs:
		clips={}
		clips[chr]=[[],[]]
		c=[]
		for line in open("{}_tiddit/clips_{}_{}.fa".format(prefix,sample_id,chr)):
			if line[0] == ">":
				c.append(line.strip())
				pos=int(line.strip().split("|")[-1])
			else:
				c.append(line.strip())
				clips[chr][0].append( "\n".join(c) )
				clips[chr][1].append([pos,0])
				c=[]
				
		
		clusters,cluster_id = DBSCAN.x_coordinate_clustering(numpy.array(clips[chr][1]),50,args.l)
		cluster_stats={}

		for i in range(0,len(clusters)):
			if clusters[i] == -1:
				continue
			if not clusters[i] in cluster_stats:
				cluster_stats[clusters[i]]=[0,[]]
			cluster_stats[clusters[i]][0]+=1
			cluster_stats[clusters[i]][1].append( clips[chr][1][i][0] )

		for i in range(0,len(clusters)):
			if clusters[i] == -1:
				continue
			if cluster_stats[clusters[i]][0] < args.r:
				continue

			if cluster_stats[clusters[i]][0] > 2*library[ "avg_coverage_{}".format(chr) ]:
				continue

			clip_coverage=coverage_data[chr][ int(math.floor(clips[chr][1][i][0]/50.0)) ]
			if clip_coverage >  args.max_coverage/2*library[ "avg_coverage_{}".format(chr) ]:
				continue

			f.write( clips[chr][0][i].strip() +"\n")

	f.close()

	os.system("{} -dNCr {}_tiddit/clips.fa | {} assemble -l 81 - > {}_tiddit/clips.fa.assembly.mag".format(args.ropebwt2,prefix,args.fermi2,prefix))
	os.system("{} simplify -COS -d 0.8 {}_tiddit/clips.fa.assembly.mag 1> {}_tiddit/clips.fa.assembly.clean.mag 2> /dev/null".format(args.fermi2,prefix,prefix))
	os.system("{} mem -x intractg {} {}_tiddit/clips.fa.assembly.clean.mag  1> {}_tiddit/clips.sam 2> /dev/null".format(args.bwa,args.ref,prefix,prefix))

	read_contigs("{}_tiddit/clips.sam".format(prefix) , prefix, sample_id, args.z)
	
