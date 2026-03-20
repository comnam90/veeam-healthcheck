using CsvHelper.Configuration.Attributes;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace VeeamHealthCheck.Functions.Reporting.DataTypes.Tape
{
    public class CTapeJobInfo
    {
        [Name("Name")]
        public string Name { get; set; }

        [Name("Type")]
        public string Type { get; set; }

        [Name("Id")]
        public string Id { get; set; }

        [Name("Description")]
        public string Description { get; set; }

        [Name("FullBackupMediaPool")]
        public string FullBackupMediaPool { get; set; }

        [Name("IncrementalBackupMediaPool")]
        public string IncrementalBackupMediaPool { get; set; }

        [Name("ProcessIncrementalBackup")]
        public string ProcessIncrementalBackup { get; set; }

        [Name("Objects")]
        public string Objects { get; set; }

        [Name("UseHardwareCompression")]
        public string UseHardwareCompression { get; set; }

        [Name("EjectCurrentMedium")]
        public string EjectCurrentMedium { get; set; }

        [Name("ExportCurrentMediaSet")]
        public string ExportCurrentMediaSet { get; set; }

        [Name("Enabled")]
        public string Enabled { get; set; }

        [Name("NextRun")]
        public string NextRun { get; set; }

        [Name("LastResult")]
        public string LastResult { get; set; }

        [Name("LastState")]
        public string LastState { get; set; }
    }
}
