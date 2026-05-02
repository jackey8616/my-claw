---
name: career-management
description: Manage career-related research, interview preparation, and job application tracking.
tags: [career, job-hunt, interview-prep, research]
---

# Career Management

This skill governs the process of researching potential employers, analyzing job roles, preparing for interviews, and organizing related artifacts.

## Workflow

1. **Company Research**
   - Perform a multi-depth search of the company's official website, LinkedIn, and third-party review sites.
   - Identify core products, business models, and recent pivots or new product lines.
   - Evaluate legitimacy by looking for employee presence, funding history, and product availability.
   - Produce a structured research report.

2. **Role Analysis**
   - Deconstruct the job description into technical requirements and implied responsibilities.
   - Map the role to the company's current product strategy (e.g., if the company is moving from Sales AI to Dev AI, an "Orchestration Engineer" role likely focuses on the transition engine).
   - Predict the technical stack and potential pain points the company is facing.

3. **Interview Preparation**
   - Generate tailored questions for the interviewer based on the research (e.g., asking about specific product gaps or pivots).
   - Prepare talking points that align the user's background with the company's specific needs.

## Artifact Organization

All career-related outputs must be organized consistently in the vault:

- **Primary Storage**: `/vault/99-Artifacts/career/`
- **Naming Convention**: Use clear, descriptive filenames (e.g., `CompanyName-Research-Report.md`, `CompanyName-Interview-Prep.md`).
- **Structure**:
  - `/vault/99-Artifacts/career/` (Root for reports and high-level analysis)
  - `/vault/99-Artifacts/career/generated-cover-letters/` (Specific folder for cover letter iterations)

## Pitfalls & Lessons Learned

- **Avoid Case Sensitivity Errors**: Ensure the directory is always lowercase `career` to avoid creating duplicate `Career` folders.
- **Verify Product vs. Marketing**: AI startups often use aggressive marketing language (e.g., "replace the entire department"). Always look for concrete evidence of product availability (pricing pages, live demos) to distinguish between a real product and a "vaporware" wrapper.
- **Check for Strategic Pivots**: If a company's main site sells one thing but the recruiter mentions another (e.g., Jobix AI selling Sales agents but hiring for a Software Engineering platform), it signals a strategic pivot. This is a critical point for interview questioning.

## Verification
- [ ] Research report is comprehensive and stored in `/vault/99-Artifacts/career/`.
- [ ] No duplicate case-variant directories exist.
- [ ] Role analysis is linked to actual product goals, not just keyword matching.
