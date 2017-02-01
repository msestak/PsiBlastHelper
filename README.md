# NAME

PsiBlastHelper - It's modulino that splits fasta input file into number of chunks for BLAST, PSI-BLAST and HMMER. It also writes SGE and HTCondor scripts to run these jobs on cluster or grid.

# SYNOPSIS

    # run separately for BLAST and HMMER because application path changes

    # test example for BLAST and PSI-BLAST
    lib/PsiBlastHelper.pm --infile=t/data/dm_splicvar \
    --out=t/data/dm_chunks/ --chunk_name=dm --chunk_size=1000 --fasta_size 10000 \
    --cpu 5 --cpu_l 5 \
    --db_name=dbfull --db_path=/shared/msestak/db_full_plus --db_gz_name=dbfull_plus_format_new.tar.gz \
    --email=msestak@irb.hr --app_path=/home/msestak/ncbi-blast-2.5.0+/bin/

    # test example for HMMER
    lib/PsiBlastHelper.pm --infile=t/data/dm_splicvar \
    --out=t/data/dm_chunks/ --chunk_name=dm --chunk_size=1000 --fasta_size 10000 \
    --cpu 5 --cpu_l 5 \
    --db_name=dbfull --db_path=/shared/msestak/dbfull --db_gz_name=dbfull.gz \
    --email=msestak@irb.hr --app_path=/home/msestak/hmmer-3.1b2-linux-intel-x86_64/binaries/

    # possible options for BLAST database
    --db_name=dbfull  --db_path=/shared/msestak/db_full_plus --db_gz_name=dbfull_plus_format_new.tar.gz
    --db_name=db90    --db_path=/shared/msestak/db90_plus    --db_gz_name=db90_plus_format_new.tar.gz
    --db_name=db90old --db_path=/shared/msestak/db90old      --db_gz_name=db90old_format.tar.gz

    # options for HMMER database
    --db_name=dbfull  --db_path=/shared/msestak/dbfull --db_gz_name=dbfull.gz

# DESCRIPTION

PsiBlastHelper is modulino that splits fasta file (input) into a number of chunks for parallel BLAST++, PSI-BLAST or HMMER.
Chunks get short name + different number for each chunk (+ sufix '\_large' if larger than --fast\_size or in top N sequences by size). This is because BLAST works really slowly for large sequences and they are processed separetly one by one.
You need to provide input file, size of the chunk, chunk name and either top N or length of sequences to run separately. 
You also meed provide --cpu or --cpu\_l to split SGE or HTCondor script on this number of jobs. The idea here is to reduce a number of BLAST database copies, which can lead to failed jobs if out of disk space on specific node. This means that one job = one database copy and multiple BLAST processes.

You can also use -a (--append) to append remainder of sequences to last file or to create new file with this remainder, which is default.
After splitting sequences it also prints SGE and HTCondor jobs bash scripts.
All paths are hardcoded to ISABELLA cluster at tannat.srce.hr and CRO-NGI grid.

For help write:

    perl FastaSplit.pm -h
    perl FastaSplit.pm -m

# LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Martin Sebastijan Šestak <msestak@irb.hr>
