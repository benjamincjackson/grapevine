rule merge_and_create_new_uk_lineages:
    input:
        config["output_path"] + "/4/all_traits.csv"
    output:
        config["output_path"] + "/5/updated_traits.csv"
    log:
        config["output_path"] + "/logs/5_merge_and_create_new_uk_lineages.log"
    shell:
        """
        datafunk curate_lineages -i {input} -o {output} &> {log}
        """

rule update_metadata:
    input:
        metadata = config["output_path"] + "/3/cog_gisaid.csv",
        traits = rules.run_4_subroutine_on_lineages.output.traits,
        updated_lineages = rules.merge_and_create_new_uk_lineages.output
    params:
        export_dir = config["export_path"] + "/metadata",
        export_prefix = config["export_path"] + "/metadata/cog_global_" + config["date"],
        webhook = config["webhook"]
    output:
        traits_metadata = temp(config["output_path"] + "/5/cog_gisaid.with_traits.csv"),
        all_metadata = config["output_path"] + "/5/cog_gisaid.with_all_traits.csv"
    log:
        config["output_path"] + "/logs/5_update_metadata.log"
    shell:
        """
        fastafunk add_columns \
          --in-metadata {input.metadata} \
          --in-data {input.traits} \
          --index-column sequence_name \
          --join-on taxon \
          --new-columns uk_lineage acc_lineage del_lineage \
          --out-metadata {output.traits_metadata} &> {log} ;

        fastafunk add_columns \
          --in-metadata {output.traits_metadata} \
          --in-data {input.updated_lineages} \
          --index-column sequence_name \
          --join-on taxon \
          --new-columns uk_lineage \
          --out-metadata {output.all_metadata} &> {log}
        """

rule publish_metadata:
    input:
        metadata = rules.update_metadata.output.all_metadata,
    params:
        outdir = config["publish_path"] + "/COG_GISAID",
        prefix = config["publish_path"] + "/COG_GISAID/cog_gisaid",
        export_dir = config["export_path"] + "/metadata",
        export_prefix = config["export_path"] + "/metadata/cog_global_" + config["date"],
        webhook = config["webhook"]
    log:
        config["output_path"] + "/logs/5_publish_metadata.log"
    shell:
        """
        mkdir -p {params.outdir}
        mkdir -p {params.export_dir}
        cp {input.metadata} {params.prefix}_metadata.csv
        cp {input.metadata} {params.export_prefix}_metadata.csv
        echo "> Updated COG and GISAID metadata published to _{params.prefix}_metadata.csv_\\n" >> {log}
        echo "> and to _{params.export_prefix}_metadata.csv_\\n" >> {log}

        echo {params.webhook}

        echo '{{"text":"' > 5a_data.json
        echo "*Step 5: Updated complete metadata with UK lineages, acctrans and deltrans*\\n" >> 5a_data.json
        cat {log} >> 5a_data.json
        echo '"}}' >> 5a_data.json
        echo "webhook {params.webhook}"
        curl -X POST -H "Content-type: application/json" -d @5a_data.json {params.webhook}
        #rm 5a_data.json
        """

rule run_5_subroutine_on_lineages:
    input:
        metadata = rules.update_metadata.output.all_metadata,
        published = rules.publish_metadata.log,
        lineage = config["lineage_splits"]
    params:
        path_to_script = workflow.current_basedir,
        output_path = config["output_path"],
        publish_path = config["publish_path"],
        prefix = config["output_path"] + "/5/lineage_"
    output:
        config["output_path"] + "/5/trees_done"
    log:
        config["output_path"] + "/logs/5_run_5_subroutine_on_lineages.log"
    threads: 40
    shell:
        """
        lineages=$(cat {input.lineage} | cut -f1 -d"," | tr '\\n' '  ')
        snakemake --nolock \
          --snakefile {params.path_to_script}/5_subroutine/5_process_lineages.smk \
          --cores {threads} \
          --configfile {params.path_to_script}/5_subroutine/config.yaml \
          --config \
          output_path={params.output_path} \
          publish_path={params.publish_path} \
          lineages="$lineages" \
          metadata={input.metadata} &> {log}

        touch {output}
        """

rule generate_report:
    input:
        metadata = rules.update_metadata.output.all_metadata
    params:
        path_to_script = workflow.current_basedir + "/../Reports/UK_full_report",
        name_stem = "UK_" + config["date"]
    output:
        report = "UK_" + config["date"] + ".pdf"
    shell:
        """
        python3 {params.path_to_script}/run_report.py --m {input.metadata} --w "latest_date" --s {params.name_stem}
        sh {params.path_to_script}/call_pandoc.sh {params.name_stem}.md {params.name_stem}.pdf
        """

rule summarize_generate_report_and_cut_out_trees:
    input:
        trees_done = rules.run_5_subroutine_on_lineages.output,
        report = rules.generate_report.output.report
    params:
        webhook = config["webhook"],
        outdir = config["publish_path"] + "/COG_GISAID/trees",
        export_dir1 = config["export_path"] + "/trees/uk_lineages",
        export_dir2 = config["export_path"] + "/reports",
    log:
        config["output_path"] + "/logs/5_summarize_generate_report_and_cut_out_trees.log"
    shell:
        """
        mkdir -p {params.export_dir1}
        mkdir -p {params.export_dir2}

        cp {params.outdir}/* {params.export_dir1}
        echo "> UK lineage trees have been published in _{params.outdir}_ and _{params.export_dir1}_\\n" >> {log}
        echo ">\\n" >> {log}
        cp {input.report} {params.export_dir2}/
        echo "> COG UK weekly report has been published in _{params.outdir}_ and _{params.export_dir2}_\\n" >> {log}

        echo '{{"text":"' > 5b_data.json
        echo "*Step 5: Generate report and UK lineage trees is complete*\\n" >> 5_data.json
        cat {log} >> 5b_data.json
        echo '"}}' >> 5b_data.json
        echo "webhook {params.webhook}"
        curl -X POST -H "Content-type: application/json" -d @5b_data.json {params.webhook}
        #rm 5b_data.json
        """